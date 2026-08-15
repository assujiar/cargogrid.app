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
  parseSlaCalendarRow,
  parseSlaCalendarVersionRow,
  parseSlaPolicyRow,
  parseSlaPolicyVersionRow,
  parseTicketSlaClockRow,
  parseTicketSlaStatusForRequesterRow,
  parseTicketSlaClockEventRow,
  parseTicketRoutingRuleRow,
  parseTicketRoutingRuleVersionRow,
  parseTicketRoutingPreviewRow,
  parseTicketAssignmentCandidateRow,
  parseTicketQueueWorkloadRow,
  parseTicketAssignmentEventRow,
  parseTicketEscalationPolicyRow,
  parseTicketEscalationPolicyVersionRow,
  parseTicketEscalationLevelRow,
  parseTicketEscalationPreviewRow,
  parseTicketEscalationRow,
  parseTicketEscalationStatusForRequesterRow,
  parseTicketEscalationEventRow,
  parseTicketEscalationSuppressionRow,
  parseTicketBreachQueueRow,
  parseTicketLinkCandidateRow,
  parseTicketLinkRow,
  parseTicketLinkEventRow,
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
  type SlaCalendarRow,
  type SlaCalendarVersionRow,
  type SlaPolicyRow,
  type SlaPolicyVersionRow,
  type TicketSlaClockRow,
  type TicketSlaStatusForRequesterRow,
  type TicketSlaClockEventRow,
  type TicketRoutingRuleRow,
  type TicketRoutingRuleVersionRow,
  type TicketRoutingPreviewRow,
  type TicketAssignmentCandidateRow,
  type TicketQueueWorkloadRow,
  type TicketAssignmentEventRow,
  type TicketChannel,
  type TicketEscalationPolicyRow,
  type TicketEscalationPolicyVersionRow,
  type TicketEscalationLevelRow,
  type TicketEscalationPreviewRow,
  type TicketEscalationRow,
  type TicketEscalationStatusForRequesterRow,
  type TicketEscalationEventRow,
  type TicketEscalationSuppressionRow,
  type TicketBreachQueueRow,
  type TicketLinkEntityType,
  type TicketLinkCandidateRow,
  type TicketLinkRow,
  type TicketLinkEventRow,
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

// HRT-295 (ISS-2026-110 fix): the customer-safe counterpart to
// listTicketLinks -- calls app.list_customer_ticket_links, which genericizes
// a staff creator's identity to "Support Team" (mirrors
// listCustomerTicketMessages' own author-label substitution) instead of the
// raw internal created_by app.list_ticket_links returns. Every other
// consumer of TicketLinkRow is unaffected -- same schema, same parser.
export async function listCustomerTicketLinks(client: TicketQueryClient, ticketId: string, actorAuthUserId: string): Promise<TicketLinkRow[]> {
  const { data, error } = await client.rpc("list_customer_ticket_links", { p_ticket_id: ticketId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TicketQueryError(error.message);
  return rows(data).map(parseTicketLinkRow);
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
  readonly productArea?: string | null;
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
    p_product_area: options?.productArea ?? null,
    p_limit: options?.limit ?? 50,
    p_after_id: options?.afterId ?? null,
  });
  if (error) throw new TicketQueryError(error.message);
  return rows(data).map(parsePlatformHelpdeskTicketListRow);
}

// ===========================================================================
// HRT-289 (CG-S12-HRT-017): SLA read queries. Mirrors
// supabase/migrations/20260731120000_create_ticket_sla.sql. Extends this
// module rather than a sibling one -- see the contract file's own header for
// the documented reasoning.
// ===========================================================================

export async function listSlaCalendars(client: TicketQueryClient, tenantId: string, actorAuthUserId: string): Promise<SlaCalendarRow[]> {
  const { data, error } = await client.rpc("list_sla_calendars", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TicketQueryError(error.message);
  return rows(data).map(parseSlaCalendarRow);
}

export async function listSlaCalendarVersions(client: TicketQueryClient, calendarId: string, actorAuthUserId: string): Promise<SlaCalendarVersionRow[]> {
  const { data, error } = await client.rpc("list_sla_calendar_versions", { p_calendar_id: calendarId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TicketQueryError(error.message);
  return rows(data).map(parseSlaCalendarVersionRow);
}

export async function listSlaPolicies(client: TicketQueryClient, tenantId: string, actorAuthUserId: string): Promise<SlaPolicyRow[]> {
  const { data, error } = await client.rpc("list_sla_policies", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TicketQueryError(error.message);
  return rows(data).map(parseSlaPolicyRow);
}

export async function listSlaPolicyVersions(client: TicketQueryClient, policyId: string, actorAuthUserId: string): Promise<SlaPolicyVersionRow[]> {
  const { data, error } = await client.rpc("list_sla_policy_versions", { p_policy_id: policyId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TicketQueryError(error.message);
  return rows(data).map(parseSlaPolicyVersionRow);
}

export async function getTicketSlaClock(client: TicketQueryClient, ticketId: string, actorAuthUserId: string): Promise<TicketSlaClockRow | null> {
  const { data, error } = await client.rpc("get_ticket_sla_clock", { p_ticket_id: ticketId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TicketQueryError(error.message);
  const row = rows(data)[0];
  return row ? parseTicketSlaClockRow(row) : null;
}

// The customer/requester-safe projection -- deliberately narrower than
// getTicketSlaClock above (security impact section 16). Never derive the
// customer-facing SLA badge from getTicketSlaClock's own richer row.
export async function getTicketSlaStatusForRequester(client: TicketQueryClient, ticketId: string, actorAuthUserId: string): Promise<TicketSlaStatusForRequesterRow | null> {
  const { data, error } = await client.rpc("get_ticket_sla_status_for_requester", { p_ticket_id: ticketId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TicketQueryError(error.message);
  const row = rows(data)[0];
  return row ? parseTicketSlaStatusForRequesterRow(row) : null;
}

export async function listTicketSlaClockEvents(client: TicketQueryClient, ticketId: string, actorAuthUserId: string): Promise<TicketSlaClockEventRow[]> {
  const { data, error } = await client.rpc("list_ticket_sla_clock_events", { p_ticket_id: ticketId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TicketQueryError(error.message);
  return rows(data).map(parseTicketSlaClockEventRow);
}

export interface TicketSlaEventForRequesterRow {
  readonly phase: "response" | "resolution";
  readonly eventType: "met" | "breached";
  readonly occurredAt: string;
}

export async function listTicketSlaEventsForRequester(client: TicketQueryClient, ticketId: string, actorAuthUserId: string): Promise<TicketSlaEventForRequesterRow[]> {
  const { data, error } = await client.rpc("list_ticket_sla_events_for_requester", { p_ticket_id: ticketId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TicketQueryError(error.message);
  return rows(data).map((row) => ({
    phase: row.phase as "response" | "resolution",
    eventType: row.event_type as "met" | "breached",
    occurredAt: row.occurred_at as string,
  }));
}

export async function getPlatformHelpdeskTicket(client: TicketQueryClient, ticketId: string, actorAuthUserId: string): Promise<PlatformHelpdeskTicketDetail | null> {
  const { data, error } = await client.rpc("get_platform_helpdesk_ticket", { p_ticket_id: ticketId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TicketQueryError(error.message);
  const row = rows(data)[0];
  return row ? parsePlatformHelpdeskTicketDetail(row) : null;
}

// ===========================================================================
// HRT-290 (CG-S12-HRT-018): Ticket Assignment read queries. Mirrors
// supabase/migrations/20260731140000_create_ticket_assignment.sql.
// ===========================================================================

export async function listTicketRoutingRules(client: TicketQueryClient, tenantId: string, actorAuthUserId: string): Promise<TicketRoutingRuleRow[]> {
  const { data, error } = await client.rpc("list_ticket_routing_rules", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TicketQueryError(error.message);
  return rows(data).map(parseTicketRoutingRuleRow);
}

export async function listTicketRoutingRuleVersions(client: TicketQueryClient, ruleId: string, actorAuthUserId: string): Promise<TicketRoutingRuleVersionRow[]> {
  const { data, error } = await client.rpc("list_ticket_routing_rule_versions", { p_rule_id: ruleId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TicketQueryError(error.message);
  return rows(data).map(parseTicketRoutingRuleVersionRow);
}

export async function previewTicketRouting(
  client: TicketQueryClient,
  tenantId: string,
  channel: TicketChannel,
  categoryId: string | null,
  priority: string | null,
  actorAuthUserId: string,
): Promise<TicketRoutingPreviewRow | null> {
  const { data, error } = await client.rpc("preview_ticket_routing", {
    p_tenant_id: tenantId,
    p_channel: channel,
    p_category_id: categoryId,
    p_priority: priority,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) throw new TicketQueryError(error.message);
  const row = rows(data)[0];
  return row ? parseTicketRoutingPreviewRow(row) : null;
}

// Powers the assignment drawer's own "explainable eligibility" (section 15)
// -- every active queue member of this ticket's own queue, never a raw
// employee directory.
export async function listTicketAssignmentCandidates(client: TicketQueryClient, ticketId: string, actorAuthUserId: string): Promise<TicketAssignmentCandidateRow[]> {
  const { data, error } = await client.rpc("list_ticket_assignment_candidates", { p_ticket_id: ticketId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TicketQueryError(error.message);
  return rows(data).map(parseTicketAssignmentCandidateRow);
}

// Read-only workload aggregation (decision 1 -- never a second source of
// truth for who is assigned).
export async function getTicketQueueWorkload(client: TicketQueryClient, queueId: string, actorAuthUserId: string): Promise<TicketQueueWorkloadRow[]> {
  const { data, error } = await client.rpc("get_ticket_queue_workload", { p_queue_id: queueId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TicketQueryError(error.message);
  return rows(data).map(parseTicketQueueWorkloadRow);
}

export async function listTicketAssignmentEvents(client: TicketQueryClient, ticketId: string, actorAuthUserId: string): Promise<TicketAssignmentEventRow[]> {
  const { data, error } = await client.rpc("list_ticket_assignment_events", { p_ticket_id: ticketId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TicketQueryError(error.message);
  return rows(data).map(parseTicketAssignmentEventRow);
}

// ===========================================================================
// HRT-291 (CG-S12-HRT-019): Ticket Escalation read queries. Mirrors
// supabase/migrations/20260731160000_create_ticket_escalation.sql.
// ===========================================================================

export async function listTicketEscalationPolicies(client: TicketQueryClient, tenantId: string, actorAuthUserId: string): Promise<TicketEscalationPolicyRow[]> {
  const { data, error } = await client.rpc("list_ticket_escalation_policies", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TicketQueryError(error.message);
  return rows(data).map(parseTicketEscalationPolicyRow);
}

export async function listTicketEscalationPolicyVersions(client: TicketQueryClient, policyId: string, actorAuthUserId: string): Promise<TicketEscalationPolicyVersionRow[]> {
  const { data, error } = await client.rpc("list_ticket_escalation_policy_versions", { p_policy_id: policyId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TicketQueryError(error.message);
  return rows(data).map(parseTicketEscalationPolicyVersionRow);
}

export async function listTicketEscalationLevels(client: TicketQueryClient, policyVersionId: string, actorAuthUserId: string): Promise<TicketEscalationLevelRow[]> {
  const { data, error } = await client.rpc("list_ticket_escalation_levels", { p_policy_version_id: policyVersionId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TicketQueryError(error.message);
  return rows(data).map(parseTicketEscalationLevelRow);
}

export async function previewTicketEscalation(
  client: TicketQueryClient,
  tenantId: string,
  channel: TicketChannel,
  categoryId: string | null,
  priority: string | null,
  queueId: string | null,
  actorAuthUserId: string,
): Promise<TicketEscalationPreviewRow | null> {
  const { data, error } = await client.rpc("preview_ticket_escalation", {
    p_tenant_id: tenantId,
    p_channel: channel,
    p_category_id: categoryId,
    p_priority: priority,
    p_queue_id: queueId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) throw new TicketQueryError(error.message);
  const row = rows(data)[0];
  return row ? parseTicketEscalationPreviewRow(row) : null;
}

// Staff-only full projection -- never the customer/requester-safe row below.
export async function getTicketEscalation(client: TicketQueryClient, ticketId: string, actorAuthUserId: string): Promise<TicketEscalationRow | null> {
  const { data, error } = await client.rpc("get_ticket_escalation", { p_ticket_id: ticketId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TicketQueryError(error.message);
  const row = rows(data)[0];
  return row ? parseTicketEscalationRow(row) : null;
}

// The customer/requester-safe projection -- deliberately narrower than
// getTicketEscalation above (security impact section 16). Never derive the
// customer-facing badge from getTicketEscalation's own richer row.
export async function getTicketEscalationStatusForRequester(client: TicketQueryClient, ticketId: string, actorAuthUserId: string): Promise<TicketEscalationStatusForRequesterRow | null> {
  const { data, error } = await client.rpc("get_ticket_escalation_status_for_requester", { p_ticket_id: ticketId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TicketQueryError(error.message);
  const row = rows(data)[0];
  return row ? parseTicketEscalationStatusForRequesterRow(row) : null;
}

export async function listTicketEscalationEvents(client: TicketQueryClient, ticketId: string, actorAuthUserId: string): Promise<TicketEscalationEventRow[]> {
  const { data, error } = await client.rpc("list_ticket_escalation_events", { p_ticket_id: ticketId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TicketQueryError(error.message);
  return rows(data).map(parseTicketEscalationEventRow);
}

export async function listTicketEscalationSuppressions(client: TicketQueryClient, ticketId: string, actorAuthUserId: string): Promise<TicketEscalationSuppressionRow[]> {
  const { data, error } = await client.rpc("list_ticket_escalation_suppressions", { p_ticket_id: ticketId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TicketQueryError(error.message);
  return rows(data).map(parseTicketEscalationSuppressionRow);
}

export interface ListTicketBreachQueueOptions {
  readonly minLevel?: number | null;
  readonly limit?: number;
  readonly afterId?: string | null;
}

// The breach/stuck queue browser (decision 13, a dedicated minimal view --
// never a widened listTickets/listMyTickets).
export async function listTicketBreachQueue(client: TicketQueryClient, tenantId: string, actorAuthUserId: string, options?: ListTicketBreachQueueOptions): Promise<TicketBreachQueueRow[]> {
  const { data, error } = await client.rpc("list_ticket_breach_queue", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_min_level: options?.minLevel ?? null,
    p_limit: options?.limit ?? 50,
    p_after_id: options?.afterId ?? null,
  });
  if (error) throw new TicketQueryError(error.message);
  return rows(data).map(parseTicketBreachQueueRow);
}

// ===========================================================================
// HRT-292 (CG-S12-HRT-020): Typed Ticket-Linked Records. Reads only --
// mutations (link/unlink/record-denial/record-summary-access) live in
// server/mutations/ticketing.ts, matching the established split for every
// other capability in this file.
// ===========================================================================

// Bounded, principal-scoped, already-authorized candidates (C-05: never a
// row the caller cannot independently see) for the given entity_type.
export async function searchTicketLinkCandidates(
  client: TicketQueryClient,
  ticketId: string,
  entityType: TicketLinkEntityType,
  searchText: string | null,
  actorAuthUserId: string,
  limit?: number,
): Promise<TicketLinkCandidateRow[]> {
  const { data, error } = await client.rpc("search_ticket_link_candidates", {
    p_ticket_id: ticketId,
    p_entity_type: entityType,
    p_search_text: searchText,
    p_actor_auth_user_id: actorAuthUserId,
    p_limit: limit ?? 20,
  });
  if (error) throw new TicketQueryError(error.message);
  return rows(data).map(parseTicketLinkCandidateRow);
}

// Every active link's label/detail/statusLabel is a LIVE, principal-fresh
// re-check (decision 6 of the migration) -- never the row's own stored
// safe_snapshot, which exists only as link-time history.
export async function listTicketLinks(client: TicketQueryClient, ticketId: string, actorAuthUserId: string): Promise<TicketLinkRow[]> {
  const { data, error } = await client.rpc("list_ticket_links", { p_ticket_id: ticketId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TicketQueryError(error.message);
  return rows(data).map(parseTicketLinkRow);
}

export interface ListTicketLinkEventsOptions {
  readonly cursorOccurredAt?: string | null;
  readonly cursorId?: string | null;
  readonly limit?: number;
}

// Staff-only (app.is_ticket_staff) ledger of link/unlink/denial/access
// events -- cursor-paginated, never OFFSET.
export async function listTicketLinkEvents(client: TicketQueryClient, ticketId: string, actorAuthUserId: string, options?: ListTicketLinkEventsOptions): Promise<TicketLinkEventRow[]> {
  const { data, error } = await client.rpc("list_ticket_link_events", {
    p_ticket_id: ticketId,
    p_actor_auth_user_id: actorAuthUserId,
    p_cursor_occurred_at: options?.cursorOccurredAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) throw new TicketQueryError(error.message);
  return rows(data).map(parseTicketLinkEventRow);
}
