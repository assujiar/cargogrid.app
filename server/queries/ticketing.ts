/**
 * Ticketing read queries (HRT-286/287, CG-S12-HRT-014/015). Thin, typed
 * wrappers around every read RPC in
 * supabase/migrations/20260731060000_create_ticketing_internal.sql and
 * 20260731080000_extend_ticketing_customer_channel.sql. The internal-facing
 * wrappers are unchanged in shape; HRT-287 adds the customer-facing wrappers
 * at the bottom of this file -- same module, per this task's own "one
 * canonical ticket service" instruction.
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
  parseCustomerAccountRow,
  parseCustomerTicketCategoryRow,
  parseCustomerTicketDetail,
  parseCustomerTicketListRow,
  parseCustomerTicketMessageRow,
  parseHelpdeskTicketCategoryRow,
  parseHelpdeskTicketDetail,
  parseHelpdeskTicketListRow,
  parseHelpdeskTicketMessageRow,
  parseSupportQueueRow,
  parsePlatformHelpdeskTicketListRow,
  parsePlatformHelpdeskTicketDetail,
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
  type CustomerAccountRow,
  type CustomerTicketCategoryRow,
  type CustomerTicketDetail,
  type CustomerTicketListRow,
  type CustomerTicketMessageRow,
  type HelpdeskTicketCategoryRow,
  type HelpdeskTicketDetail,
  type HelpdeskTicketListRow,
  type HelpdeskTicketMessageRow,
  type SupportQueueRow,
  type PlatformHelpdeskTicketListRow,
  type PlatformHelpdeskTicketDetail,
  type HelpdeskSeverity,
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

// --- HRT-287 (CG-S12-HRT-015): Layer 4 customer-facing read queries. Each
// calls its own dedicated, customer-safe projection RPC -- never the
// internal wrappers above with fields merely dropped client-side. ---

export async function listCustomerAccountsForActor(client: TicketQueryClient, tenantId: string, actorAuthUserId: string): Promise<CustomerAccountRow[]> {
  const { data, error } = await client.rpc("list_customer_accounts_for_actor", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TicketQueryError(error.message);
  return rows(data).map(parseCustomerAccountRow);
}

export async function listCustomerTicketCategories(client: TicketQueryClient, tenantId: string, actorAuthUserId: string): Promise<CustomerTicketCategoryRow[]> {
  const { data, error } = await client.rpc("list_customer_ticket_categories", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TicketQueryError(error.message);
  return rows(data).map(parseCustomerTicketCategoryRow);
}

export async function getCustomerTicket(client: TicketQueryClient, ticketId: string, actorAuthUserId: string): Promise<CustomerTicketDetail | null> {
  const { data, error } = await client.rpc("get_customer_ticket", { p_ticket_id: ticketId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TicketQueryError(error.message);
  const row = rows(data)[0];
  return row ? parseCustomerTicketDetail(row) : null;
}

export interface ListCustomerTicketsOptions {
  readonly accountId?: string | null;
  readonly status?: TicketStatus | null;
  readonly limit?: number;
  readonly afterId?: string | null;
}

export async function listCustomerTickets(client: TicketQueryClient, tenantId: string, actorAuthUserId: string, options?: ListCustomerTicketsOptions): Promise<CustomerTicketListRow[]> {
  const { data, error } = await client.rpc("list_customer_tickets", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_account_id: options?.accountId ?? null,
    p_status: options?.status ?? null,
    p_limit: options?.limit ?? 50,
    p_after_id: options?.afterId ?? null,
  });
  if (error) throw new TicketQueryError(error.message);
  return rows(data).map(parseCustomerTicketListRow);
}

export async function listCustomerTicketMessages(
  client: TicketQueryClient,
  ticketId: string,
  actorAuthUserId: string,
  options?: { limit?: number; afterId?: string | null },
): Promise<CustomerTicketMessageRow[]> {
  const { data, error } = await client.rpc("list_customer_ticket_messages", {
    p_ticket_id: ticketId,
    p_actor_auth_user_id: actorAuthUserId,
    p_limit: options?.limit ?? 100,
    p_after_id: options?.afterId ?? null,
  });
  if (error) throw new TicketQueryError(error.message);
  return rows(data).map(parseCustomerTicketMessageRow);
}

// --- HRT-288 (CG-S12-HRT-016): tenant-side helpdesk read queries. Each
// calls its own dedicated, tenant-safe projection RPC -- never the staff
// wrappers above with fields merely dropped client-side. ---

export async function listHelpdeskTicketCategories(client: TicketQueryClient, tenantId: string, actorAuthUserId: string): Promise<HelpdeskTicketCategoryRow[]> {
  const { data, error } = await client.rpc("list_helpdesk_ticket_categories", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TicketQueryError(error.message);
  return rows(data).map(parseHelpdeskTicketCategoryRow);
}

export async function getTenantHelpdeskTicket(client: TicketQueryClient, ticketId: string, actorAuthUserId: string): Promise<HelpdeskTicketDetail | null> {
  const { data, error } = await client.rpc("get_tenant_helpdesk_ticket", { p_ticket_id: ticketId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TicketQueryError(error.message);
  const row = rows(data)[0];
  return row ? parseHelpdeskTicketDetail(row) : null;
}

export async function listTenantHelpdeskTickets(
  client: TicketQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { status?: TicketStatus | null; limit?: number; afterId?: string | null },
): Promise<HelpdeskTicketListRow[]> {
  const { data, error } = await client.rpc("list_tenant_helpdesk_tickets", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_status: options?.status ?? null,
    p_limit: options?.limit ?? 50,
    p_after_id: options?.afterId ?? null,
  });
  if (error) throw new TicketQueryError(error.message);
  return rows(data).map(parseHelpdeskTicketListRow);
}

export async function listTenantHelpdeskTicketMessages(
  client: TicketQueryClient,
  ticketId: string,
  actorAuthUserId: string,
  options?: { limit?: number; afterId?: string | null },
): Promise<HelpdeskTicketMessageRow[]> {
  const { data, error } = await client.rpc("list_tenant_helpdesk_ticket_messages", {
    p_ticket_id: ticketId,
    p_actor_auth_user_id: actorAuthUserId,
    p_limit: options?.limit ?? 100,
    p_after_id: options?.afterId ?? null,
  });
  if (error) throw new TicketQueryError(error.message);
  return rows(data).map(parseHelpdeskTicketMessageRow);
}

// --- HRT-288: Platform-side (Supreme-Admin-facing) helpdesk read queries.
// Cross-tenant by design -- app.list_platform_helpdesk_tickets is the ONE
// deliberate cross-tenant read RPC this capability introduces. ---

export async function listSupportQueues(client: TicketQueryClient, actorAuthUserId: string): Promise<SupportQueueRow[]> {
  const { data, error } = await client.rpc("list_support_queues", { p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TicketQueryError(error.message);
  return rows(data).map(parseSupportQueueRow);
}

export interface ListPlatformHelpdeskTicketsOptions {
  readonly status?: TicketStatus | null;
  readonly severity?: HelpdeskSeverity | null;
  readonly supportQueueId?: string | null;
  readonly tenantId?: string | null;
  readonly limit?: number;
  readonly afterId?: string | null;
}

export async function listPlatformHelpdeskTickets(client: TicketQueryClient, actorAuthUserId: string, options?: ListPlatformHelpdeskTicketsOptions): Promise<PlatformHelpdeskTicketListRow[]> {
  const { data, error } = await client.rpc("list_platform_helpdesk_tickets", {
    p_actor_auth_user_id: actorAuthUserId,
    p_status: options?.status ?? null,
    p_severity: options?.severity ?? null,
    p_support_queue_id: options?.supportQueueId ?? null,
    p_tenant_id: options?.tenantId ?? null,
    p_limit: options?.limit ?? 50,
    p_after_id: options?.afterId ?? null,
  });
  if (error) throw new TicketQueryError(error.message);
  return rows(data).map(parsePlatformHelpdeskTicketListRow);
}

export async function getPlatformHelpdeskTicket(client: TicketQueryClient, ticketId: string, actorAuthUserId: string): Promise<PlatformHelpdeskTicketDetail | null> {
  const { data, error } = await client.rpc("get_platform_helpdesk_ticket", { p_ticket_id: ticketId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TicketQueryError(error.message);
  const row = rows(data)[0];
  return row ? parsePlatformHelpdeskTicketDetail(row) : null;
}
