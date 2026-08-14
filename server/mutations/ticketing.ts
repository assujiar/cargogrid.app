/**
 * Ticketing mutation primitives (HRT-286/287, CG-S12-HRT-014/015). Thin,
 * typed wrappers around every write RPC in
 * supabase/migrations/20260731060000_create_ticketing_internal.sql and
 * 20260731080000_extend_ticketing_customer_channel.sql. The internal-facing
 * wrappers are unchanged in shape; HRT-287 adds the customer-facing wrappers
 * at the bottom of this file -- same module, one canonical ticket service.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateTicketQueueInputSchema,
  CreateTicketCategoryInputSchema,
  AddTicketQueueMemberInputSchema,
  RemoveTicketQueueMemberInputSchema,
  CreateTicketInputSchema,
  CreateTicketForEmployeeInputSchema,
  ReplyToTicketInputSchema,
  RedactTicketMessageInputSchema,
  AddTicketWatcherInputSchema,
  RemoveTicketWatcherInputSchema,
  AssignTicketInputSchema,
  TransferTicketQueueInputSchema,
  UpdateTicketClassificationInputSchema,
  TransitionTicketStatusInputSchema,
  SetTicketCategoryCustomerVisibilityInputSchema,
  CreateCustomerTicketInputSchema,
  ReplyToCustomerTicketInputSchema,
  CreateHelpdeskTicketInputSchema,
  ReplyToHelpdeskTicketInputSchema,
  SetTicketCategoryHelpdeskVisibilityInputSchema,
  CreateSupportQueueInputSchema,
  AssignHelpdeskTicketInputSchema,
  TransferHelpdeskSupportQueueInputSchema,
  UpdateHelpdeskTicketClassificationInputSchema,
  LinkHelpdeskSupportGrantInputSchema,
  type CreateTicketQueueInput,
  type CreateTicketCategoryInput,
  type AddTicketQueueMemberInput,
  type RemoveTicketQueueMemberInput,
  type CreateTicketInput,
  type CreateTicketForEmployeeInput,
  type ReplyToTicketInput,
  type RedactTicketMessageInput,
  type AddTicketWatcherInput,
  type RemoveTicketWatcherInput,
  type AssignTicketInput,
  type TransferTicketQueueInput,
  type UpdateTicketClassificationInput,
  type TransitionTicketStatusInput,
  type SetTicketCategoryCustomerVisibilityInput,
  type CreateCustomerTicketInput,
  type ReplyToCustomerTicketInput,
  type CreateHelpdeskTicketInput,
  type ReplyToHelpdeskTicketInput,
  type SetTicketCategoryHelpdeskVisibilityInput,
  type CreateSupportQueueInput,
  type AssignHelpdeskTicketInput,
  type TransferHelpdeskSupportQueueInput,
  type UpdateHelpdeskTicketClassificationInput,
  type LinkHelpdeskSupportGrantInput,
  CreateSlaCalendarInputSchema,
  CreateSlaCalendarVersionInputSchema,
  AddSlaCalendarBusinessHoursInputSchema,
  AddSlaCalendarHolidayInputSchema,
  PublishSlaCalendarVersionInputSchema,
  CreateSlaPolicyInputSchema,
  CreateSlaPolicyVersionInputSchema,
  PublishSlaPolicyVersionInputSchema,
  StartTicketSlaClockInputSchema,
  PauseTicketSlaClockInputSchema,
  ResumeTicketSlaClockInputSchema,
  RecalculateTicketSlaClockInputSchema,
  RunTicketSlaEvaluationBatchInputSchema,
  type CreateSlaCalendarInput,
  type CreateSlaCalendarVersionInput,
  type AddSlaCalendarBusinessHoursInput,
  type AddSlaCalendarHolidayInput,
  type PublishSlaCalendarVersionInput,
  type CreateSlaPolicyInput,
  type CreateSlaPolicyVersionInput,
  type PublishSlaPolicyVersionInput,
  type StartTicketSlaClockInput,
  type PauseTicketSlaClockInput,
  type ResumeTicketSlaClockInput,
  type RecalculateTicketSlaClockInput,
  type RunTicketSlaEvaluationBatchInput,
  CreateTicketRoutingRuleInputSchema,
  CreateTicketRoutingRuleVersionInputSchema,
  PublishTicketRoutingRuleVersionInputSchema,
  ClaimTicketInputSchema,
  AcceptTicketAssignmentInputSchema,
  DeclineTicketAssignmentInputSchema,
  AutoRouteTicketInputSchema,
  type CreateTicketRoutingRuleInput,
  type CreateTicketRoutingRuleVersionInput,
  type PublishTicketRoutingRuleVersionInput,
  type ClaimTicketInput,
  type AcceptTicketAssignmentInput,
  type DeclineTicketAssignmentInput,
  type AutoRouteTicketInput,
  CreateTicketEscalationPolicyInputSchema,
  CreateTicketEscalationPolicyVersionInputSchema,
  AddTicketEscalationLevelInputSchema,
  PublishTicketEscalationPolicyVersionInputSchema,
  EscalateTicketInputSchema,
  AcknowledgeTicketEscalationInputSchema,
  ResolveTicketEscalationInputSchema,
  SuppressTicketEscalationInputSchema,
  RevokeTicketEscalationSuppressionInputSchema,
  RunTicketEscalationEvaluationBatchInputSchema,
  type CreateTicketEscalationPolicyInput,
  type CreateTicketEscalationPolicyVersionInput,
  type AddTicketEscalationLevelInput,
  type PublishTicketEscalationPolicyVersionInput,
  type EscalateTicketInput,
  type AcknowledgeTicketEscalationInput,
  type ResolveTicketEscalationInput,
  type SuppressTicketEscalationInput,
  type RevokeTicketEscalationSuppressionInput,
  type RunTicketEscalationEvaluationBatchInput,
  SearchTicketLinkCandidatesInputSchema,
  LinkTicketRecordInputSchema,
  UnlinkTicketRecordInputSchema,
  RecordTicketLinkAccessDenialInputSchema,
  RecordTicketLinkSummaryAccessInputSchema,
  type SearchTicketLinkCandidatesInput,
  type LinkTicketRecordInput,
  type UnlinkTicketRecordInput,
  type RecordTicketLinkAccessDenialInput,
  type RecordTicketLinkSummaryAccessInput,
} from "../contracts/ticketing/ticketing.ts";

export type TicketMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const TICKET_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "insufficient_privilege",
  "employee_not_found",
  "org_unit_not_found",
  "ticket_queue_not_found",
  "ticket_queue_member_not_found",
  "ticket_not_found",
  "ticket_message_not_found",
  "ticket_watcher_not_found",
  "category_not_available",
  "queue_not_available",
  "queue_required",
  "code_required",
  "name_required",
  "subject_required",
  "body_required",
  "reason_required",
  "invalid_priority",
  "invalid_visibility",
  "invalid_transition",
  "invalid_decision",
  "ticket_cancelled",
  "assignee_not_queue_member",
  "evidence_file_not_found",
  "evidence_file_infected",
  "evidence_file_not_scanned",
  "idempotency_key_conflict",
  "invalid_date_range",
  "stale_version",
  "ticket_category_not_found",
  "account_not_available",
  "invalid_channel",
  "invalid_requester_identity",
  "channel_not_supported",
  "invalid_severity",
  "invalid_environment",
  "assignee_not_support_staff",
  "support_queue_not_available",
  "support_grant_not_found",
  // HRT-289 (CG-S12-HRT-017): SLA error codes.
  "sla_calendar_not_found",
  "sla_calendar_version_not_found",
  "sla_policy_not_found",
  "sla_policy_version_not_found",
  "sla_policy_not_matched",
  "sla_policy_ambiguous_match",
  "sla_calendar_not_published",
  "calendar_incomplete",
  "invalid_timezone",
  "timezone_required",
  "invalid_pause_reason",
  "ticket_sla_clock_not_found",
  // HRT-290 (CG-S12-HRT-018): Ticket Assignment error codes.
  "ticket_routing_rule_not_found",
  "ticket_routing_rule_version_not_found",
  "ticket_routing_rule_ambiguous_match",
  "ticket_routing_rule_not_matched",
  "invalid_assignment_mode",
  "invalid_workload_limit",
  "invalid_state",
  "ticket_already_assigned",
  "employee_not_eligible",
  "workload_limit_exceeded",
  // HRT-291 (CG-S12-HRT-019): Ticket Escalation error codes.
  "ticket_escalation_policy_not_found",
  "ticket_escalation_policy_version_not_found",
  "ticket_escalation_policy_ambiguous_match",
  "escalation_policy_incomplete",
  "invalid_level_number",
  "invalid_trigger_type",
  "threshold_minutes_required",
  "threshold_minutes_not_applicable",
  "min_priority_required",
  "invalid_target_type",
  "invalid_target",
  "escalation_target_not_eligible",
  "escalation_suppressed",
  "escalation_already_suppressed",
  "invalid_expiry",
  "ticket_escalation_not_found",
  "ticket_escalation_suppression_not_found",
  "invalid_period",
  // HRT-292 (CG-S12-HRT-020): Typed Ticket-Linked Records error codes.
  "unsupported_entity_type",
  "entity_type_not_permitted",
  "invalid_relationship",
  "record_not_eligible",
  "ticket_link_not_found",
  "invalid_access_type",
] as const;

export type KnownTicketMutationErrorCode = (typeof TICKET_KNOWN_MUTATION_ERROR_CODES)[number];
export type TicketMutationErrorCode = KnownTicketMutationErrorCode | "mutation_failed";

export class TicketMutationError extends Error {
  readonly code: TicketMutationErrorCode;

  constructor(code: TicketMutationErrorCode, message: string) {
    super(message);
    this.name = "TicketMutationError";
    this.code = code;
  }
}

function classifyError(message: string): TicketMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  if (prefix && (TICKET_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix)) {
    return prefix as KnownTicketMutationErrorCode;
  }
  return "mutation_failed";
}

async function callRpc<T>(client: TicketMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await client.rpc(fn, args);
  if (error) throw new TicketMutationError(classifyError(error.message), error.message);
  return data as T;
}

export async function createTicketQueue(client: TicketMutationRpcClient, input: CreateTicketQueueInput) {
  const v = CreateTicketQueueInputSchema.parse(input);
  return callRpc(client, "create_ticket_queue", {
    p_tenant_id: v.tenantId,
    p_org_unit_id: v.orgUnitId,
    p_code: v.code,
    p_name: v.name,
    p_description: v.description,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function createTicketCategory(client: TicketMutationRpcClient, input: CreateTicketCategoryInput) {
  const v = CreateTicketCategoryInputSchema.parse(input);
  return callRpc(client, "create_ticket_category", {
    p_tenant_id: v.tenantId,
    p_code: v.code,
    p_name: v.name,
    p_default_queue_id: v.defaultQueueId,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function addTicketQueueMember(client: TicketMutationRpcClient, input: AddTicketQueueMemberInput) {
  const v = AddTicketQueueMemberInputSchema.parse(input);
  return callRpc(client, "add_ticket_queue_member", {
    p_queue_id: v.queueId,
    p_employee_id: v.employeeId,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function removeTicketQueueMember(client: TicketMutationRpcClient, input: RemoveTicketQueueMemberInput) {
  const v = RemoveTicketQueueMemberInputSchema.parse(input);
  return callRpc(client, "remove_ticket_queue_member", {
    p_member_id: v.memberId,
    p_expected_version: v.expectedVersion,
    p_reason: v.reason,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function createTicket(client: TicketMutationRpcClient, input: CreateTicketInput) {
  const v = CreateTicketInputSchema.parse(input);
  return callRpc(client, "create_ticket", {
    p_tenant_id: v.tenantId,
    p_category_id: v.categoryId,
    p_queue_id: v.queueId,
    p_priority: v.priority,
    p_subject: v.subject,
    p_body: v.body,
    p_idempotency_key: v.idempotencyKey,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function createTicketForEmployee(client: TicketMutationRpcClient, input: CreateTicketForEmployeeInput) {
  const v = CreateTicketForEmployeeInputSchema.parse(input);
  return callRpc(client, "create_ticket_for_employee", {
    p_tenant_id: v.tenantId,
    p_requester_employee_id: v.requesterEmployeeId,
    p_category_id: v.categoryId,
    p_queue_id: v.queueId,
    p_priority: v.priority,
    p_subject: v.subject,
    p_body: v.body,
    p_idempotency_key: v.idempotencyKey,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function replyToTicket(client: TicketMutationRpcClient, input: ReplyToTicketInput) {
  const v = ReplyToTicketInputSchema.parse(input);
  return callRpc(client, "reply_to_ticket", {
    p_ticket_id: v.ticketId,
    p_body: v.body,
    p_visibility: v.visibility,
    p_attachment_file_ids: v.attachmentFileIds,
    p_idempotency_key: v.idempotencyKey,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function redactTicketMessage(client: TicketMutationRpcClient, input: RedactTicketMessageInput) {
  const v = RedactTicketMessageInputSchema.parse(input);
  return callRpc(client, "redact_ticket_message", {
    p_message_id: v.messageId,
    p_expected_version: v.expectedVersion,
    p_reason: v.reason,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function addTicketWatcher(client: TicketMutationRpcClient, input: AddTicketWatcherInput) {
  const v = AddTicketWatcherInputSchema.parse(input);
  return callRpc(client, "add_ticket_watcher", {
    p_ticket_id: v.ticketId,
    p_employee_id: v.employeeId,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function removeTicketWatcher(client: TicketMutationRpcClient, input: RemoveTicketWatcherInput) {
  const v = RemoveTicketWatcherInputSchema.parse(input);
  return callRpc(client, "remove_ticket_watcher", {
    p_watcher_id: v.watcherId,
    p_expected_version: v.expectedVersion,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function assignTicket(client: TicketMutationRpcClient, input: AssignTicketInput) {
  const v = AssignTicketInputSchema.parse(input);
  return callRpc(client, "assign_ticket", {
    p_ticket_id: v.ticketId,
    p_expected_version: v.expectedVersion,
    p_assignee_employee_id: v.assigneeEmployeeId,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
    p_reason: v.reason ?? null,
    p_override_workload_limit: v.overrideWorkloadLimit ?? false,
  });
}

export async function transferTicketQueue(client: TicketMutationRpcClient, input: TransferTicketQueueInput) {
  const v = TransferTicketQueueInputSchema.parse(input);
  return callRpc(client, "transfer_ticket_queue", {
    p_ticket_id: v.ticketId,
    p_expected_version: v.expectedVersion,
    p_new_queue_id: v.newQueueId,
    p_reason: v.reason,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function updateTicketClassification(client: TicketMutationRpcClient, input: UpdateTicketClassificationInput) {
  const v = UpdateTicketClassificationInputSchema.parse(input);
  return callRpc(client, "update_ticket_classification", {
    p_ticket_id: v.ticketId,
    p_expected_version: v.expectedVersion,
    p_category_id: v.categoryId,
    p_priority: v.priority,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function transitionTicketStatus(client: TicketMutationRpcClient, input: TransitionTicketStatusInput) {
  const v = TransitionTicketStatusInputSchema.parse(input);
  return callRpc(client, "transition_ticket_status", {
    p_ticket_id: v.ticketId,
    p_expected_version: v.expectedVersion,
    p_to_status: v.toStatus,
    p_reason: v.reason,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function setTicketCategoryCustomerVisibility(client: TicketMutationRpcClient, input: SetTicketCategoryCustomerVisibilityInput) {
  const v = SetTicketCategoryCustomerVisibilityInputSchema.parse(input);
  return callRpc(client, "set_ticket_category_customer_visibility", {
    p_category_id: v.categoryId,
    p_customer_visible: v.customerVisible,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

// --- HRT-287 (CG-S12-HRT-015): Layer 4 customer-facing mutations. Scope is
// always derived from authenticated membership at the RPC layer
// (app.resolve_customer_owner_account_scope) -- these wrappers never trust
// or re-derive scope themselves, matching business rule (section 24). ---

export async function createCustomerTicket(client: TicketMutationRpcClient, input: CreateCustomerTicketInput) {
  const v = CreateCustomerTicketInputSchema.parse(input);
  return callRpc(client, "create_customer_ticket", {
    p_tenant_id: v.tenantId,
    p_account_id: v.accountId,
    p_category_id: v.categoryId,
    p_priority: v.priority,
    p_subject: v.subject,
    p_body: v.body,
    p_idempotency_key: v.idempotencyKey,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function replyToCustomerTicket(client: TicketMutationRpcClient, input: ReplyToCustomerTicketInput) {
  const v = ReplyToCustomerTicketInputSchema.parse(input);
  return callRpc(client, "reply_to_customer_ticket", {
    p_ticket_id: v.ticketId,
    p_body: v.body,
    p_attachment_file_ids: v.attachmentFileIds,
    p_idempotency_key: v.idempotencyKey,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

// --- HRT-288 (CG-S12-HRT-016): tenant-side helpdesk mutations. Authority is
// always derived server-side (app._is_tenant_helpdesk_authorized) -- these
// wrappers never trust or re-derive scope, they only forward. ---

export async function createHelpdeskTicket(client: TicketMutationRpcClient, input: CreateHelpdeskTicketInput) {
  const v = CreateHelpdeskTicketInputSchema.parse(input);
  return callRpc(client, "create_helpdesk_ticket", {
    p_tenant_id: v.tenantId,
    p_category_id: v.categoryId,
    p_priority: v.priority,
    p_severity: v.severity,
    p_product_area: v.productArea,
    p_environment: v.environment,
    p_external_reference: v.externalReference,
    p_subject: v.subject,
    p_body: v.body,
    p_idempotency_key: v.idempotencyKey,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function replyToHelpdeskTicket(client: TicketMutationRpcClient, input: ReplyToHelpdeskTicketInput) {
  const v = ReplyToHelpdeskTicketInputSchema.parse(input);
  return callRpc(client, "reply_to_helpdesk_ticket", {
    p_ticket_id: v.ticketId,
    p_body: v.body,
    p_attachment_file_ids: v.attachmentFileIds,
    p_idempotency_key: v.idempotencyKey,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function setTicketCategoryHelpdeskVisibility(client: TicketMutationRpcClient, input: SetTicketCategoryHelpdeskVisibilityInput) {
  const v = SetTicketCategoryHelpdeskVisibilityInputSchema.parse(input);
  return callRpc(client, "set_ticket_category_helpdesk_visibility", {
    p_category_id: v.categoryId,
    p_helpdesk_visible: v.helpdeskVisible,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

// --- HRT-288: Platform-side (Supreme-Admin-gated) helpdesk mutations. ---

export async function createSupportQueue(client: TicketMutationRpcClient, input: CreateSupportQueueInput) {
  const v = CreateSupportQueueInputSchema.parse(input);
  return callRpc(client, "create_support_queue", {
    p_code: v.code,
    p_name: v.name,
    p_description: v.description,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function assignHelpdeskTicket(client: TicketMutationRpcClient, input: AssignHelpdeskTicketInput) {
  const v = AssignHelpdeskTicketInputSchema.parse(input);
  return callRpc(client, "assign_helpdesk_ticket", {
    p_ticket_id: v.ticketId,
    p_expected_version: v.expectedVersion,
    p_assignee_auth_user_id: v.assigneeAuthUserId,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function transferHelpdeskSupportQueue(client: TicketMutationRpcClient, input: TransferHelpdeskSupportQueueInput) {
  const v = TransferHelpdeskSupportQueueInputSchema.parse(input);
  return callRpc(client, "transfer_helpdesk_support_queue", {
    p_ticket_id: v.ticketId,
    p_expected_version: v.expectedVersion,
    p_new_support_queue_id: v.newSupportQueueId,
    p_reason: v.reason,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function updateHelpdeskTicketClassification(client: TicketMutationRpcClient, input: UpdateHelpdeskTicketClassificationInput) {
  const v = UpdateHelpdeskTicketClassificationInputSchema.parse(input);
  return callRpc(client, "update_helpdesk_ticket_classification", {
    p_ticket_id: v.ticketId,
    p_expected_version: v.expectedVersion,
    p_category_id: v.categoryId,
    p_priority: v.priority,
    p_severity: v.severity,
    p_product_area: v.productArea,
    p_environment: v.environment,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function linkHelpdeskSupportGrant(client: TicketMutationRpcClient, input: LinkHelpdeskSupportGrantInput) {
  const v = LinkHelpdeskSupportGrantInputSchema.parse(input);
  return callRpc(client, "link_helpdesk_support_grant", {
    p_ticket_id: v.ticketId,
    p_expected_version: v.expectedVersion,
    p_case_ref: v.caseRef,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

// ===========================================================================
// HRT-289 (CG-S12-HRT-017): SLA mutation wrappers. Mirrors
// supabase/migrations/20260731120000_create_ticket_sla.sql.
// ===========================================================================

export async function createSlaCalendar(client: TicketMutationRpcClient, input: CreateSlaCalendarInput) {
  const v = CreateSlaCalendarInputSchema.parse(input);
  return callRpc(client, "create_sla_calendar", {
    p_tenant_id: v.tenantId,
    p_code: v.code,
    p_name: v.name,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function createSlaCalendarVersion(client: TicketMutationRpcClient, input: CreateSlaCalendarVersionInput) {
  const v = CreateSlaCalendarVersionInputSchema.parse(input);
  return callRpc(client, "create_sla_calendar_version", {
    p_calendar_id: v.calendarId,
    p_timezone: v.timezone,
    p_is_24x7: v.is24x7,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function addSlaCalendarBusinessHours(client: TicketMutationRpcClient, input: AddSlaCalendarBusinessHoursInput) {
  const v = AddSlaCalendarBusinessHoursInputSchema.parse(input);
  return callRpc(client, "add_sla_calendar_business_hours", {
    p_calendar_version_id: v.calendarVersionId,
    p_day_of_week: v.dayOfWeek,
    p_start_time: v.startTime,
    p_end_time: v.endTime,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function addSlaCalendarHoliday(client: TicketMutationRpcClient, input: AddSlaCalendarHolidayInput) {
  const v = AddSlaCalendarHolidayInputSchema.parse(input);
  return callRpc(client, "add_sla_calendar_holiday", {
    p_calendar_version_id: v.calendarVersionId,
    p_holiday_date: v.holidayDate,
    p_name: v.name,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function publishSlaCalendarVersion(client: TicketMutationRpcClient, input: PublishSlaCalendarVersionInput) {
  const v = PublishSlaCalendarVersionInputSchema.parse(input);
  return callRpc(client, "publish_sla_calendar_version", {
    p_version_id: v.versionId,
    p_expected_version: v.expectedVersion,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function createSlaPolicy(client: TicketMutationRpcClient, input: CreateSlaPolicyInput) {
  const v = CreateSlaPolicyInputSchema.parse(input);
  return callRpc(client, "create_sla_policy", {
    p_tenant_id: v.tenantId,
    p_code: v.code,
    p_name: v.name,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function createSlaPolicyVersion(client: TicketMutationRpcClient, input: CreateSlaPolicyVersionInput) {
  const v = CreateSlaPolicyVersionInputSchema.parse(input);
  return callRpc(client, "create_sla_policy_version", {
    p_policy_id: v.policyId,
    p_channel: v.channel,
    p_category_id: v.categoryId,
    p_priority: v.priority,
    p_customer_account_id: v.customerAccountId,
    p_queue_id: v.queueId,
    p_support_queue_id: v.supportQueueId,
    p_calendar_id: v.calendarId,
    p_response_target_minutes: v.responseTargetMinutes,
    p_resolution_target_minutes: v.resolutionTargetMinutes,
    p_precedence_rank: v.precedenceRank,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function publishSlaPolicyVersion(client: TicketMutationRpcClient, input: PublishSlaPolicyVersionInput) {
  const v = PublishSlaPolicyVersionInputSchema.parse(input);
  return callRpc(client, "publish_sla_policy_version", {
    p_version_id: v.versionId,
    p_expected_version: v.expectedVersion,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function startTicketSlaClock(client: TicketMutationRpcClient, input: StartTicketSlaClockInput) {
  const v = StartTicketSlaClockInputSchema.parse(input);
  return callRpc(client, "start_ticket_sla_clock", {
    p_ticket_id: v.ticketId,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function pauseTicketSlaClock(client: TicketMutationRpcClient, input: PauseTicketSlaClockInput) {
  const v = PauseTicketSlaClockInputSchema.parse(input);
  return callRpc(client, "pause_ticket_sla_clock", {
    p_ticket_id: v.ticketId,
    p_expected_version: v.expectedVersion,
    p_pause_reason_code: v.pauseReasonCode,
    p_reason: v.reason,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function resumeTicketSlaClock(client: TicketMutationRpcClient, input: ResumeTicketSlaClockInput) {
  const v = ResumeTicketSlaClockInputSchema.parse(input);
  return callRpc(client, "resume_ticket_sla_clock", {
    p_ticket_id: v.ticketId,
    p_expected_version: v.expectedVersion,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function recalculateTicketSlaClock(client: TicketMutationRpcClient, input: RecalculateTicketSlaClockInput) {
  const v = RecalculateTicketSlaClockInputSchema.parse(input);
  return callRpc(client, "recalculate_ticket_sla_clock", {
    p_ticket_id: v.ticketId,
    p_expected_version: v.expectedVersion,
    p_reason: v.reason,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function runTicketSlaEvaluationBatch(client: TicketMutationRpcClient, input: RunTicketSlaEvaluationBatchInput) {
  const v = RunTicketSlaEvaluationBatchInputSchema.parse(input);
  return callRpc(client, "run_ticket_sla_evaluation_batch", {
    p_tenant_id: v.tenantId,
    p_as_of: v.asOf,
    p_period_label: v.periodLabel,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

// ===========================================================================
// HRT-290 (CG-S12-HRT-018): Ticket Assignment mutation wrappers. Mirrors
// supabase/migrations/20260731140000_create_ticket_assignment.sql.
// ===========================================================================

export async function createTicketRoutingRule(client: TicketMutationRpcClient, input: CreateTicketRoutingRuleInput) {
  const v = CreateTicketRoutingRuleInputSchema.parse(input);
  return callRpc(client, "create_ticket_routing_rule", {
    p_tenant_id: v.tenantId,
    p_code: v.code,
    p_name: v.name,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function createTicketRoutingRuleVersion(client: TicketMutationRpcClient, input: CreateTicketRoutingRuleVersionInput) {
  const v = CreateTicketRoutingRuleVersionInputSchema.parse(input);
  return callRpc(client, "create_ticket_routing_rule_version", {
    p_rule_id: v.ruleId,
    p_channel: v.channel,
    p_category_id: v.categoryId,
    p_priority: v.priority,
    p_target_queue_id: v.targetQueueId,
    p_assignment_mode: v.assignmentMode,
    p_max_active_assignments_per_member: v.maxActiveAssignmentsPerMember,
    p_precedence_rank: v.precedenceRank,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function publishTicketRoutingRuleVersion(client: TicketMutationRpcClient, input: PublishTicketRoutingRuleVersionInput) {
  const v = PublishTicketRoutingRuleVersionInputSchema.parse(input);
  return callRpc(client, "publish_ticket_routing_rule_version", {
    p_version_id: v.versionId,
    p_expected_version: v.expectedVersion,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function claimTicket(client: TicketMutationRpcClient, input: ClaimTicketInput) {
  const v = ClaimTicketInputSchema.parse(input);
  return callRpc(client, "claim_ticket", {
    p_ticket_id: v.ticketId,
    p_expected_version: v.expectedVersion,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function acceptTicketAssignment(client: TicketMutationRpcClient, input: AcceptTicketAssignmentInput) {
  const v = AcceptTicketAssignmentInputSchema.parse(input);
  return callRpc(client, "accept_ticket_assignment", {
    p_ticket_id: v.ticketId,
    p_expected_version: v.expectedVersion,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function declineTicketAssignment(client: TicketMutationRpcClient, input: DeclineTicketAssignmentInput) {
  const v = DeclineTicketAssignmentInputSchema.parse(input);
  return callRpc(client, "decline_ticket_assignment", {
    p_ticket_id: v.ticketId,
    p_expected_version: v.expectedVersion,
    p_reason: v.reason,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function autoRouteTicket(client: TicketMutationRpcClient, input: AutoRouteTicketInput) {
  const v = AutoRouteTicketInputSchema.parse(input);
  return callRpc(client, "auto_route_ticket", {
    p_ticket_id: v.ticketId,
    p_expected_version: v.expectedVersion,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

// ===========================================================================
// HRT-291 (CG-S12-HRT-019): Ticket Escalation mutation wrappers. Mirrors
// supabase/migrations/20260731160000_create_ticket_escalation.sql.
// ===========================================================================

export async function createTicketEscalationPolicy(client: TicketMutationRpcClient, input: CreateTicketEscalationPolicyInput) {
  const v = CreateTicketEscalationPolicyInputSchema.parse(input);
  return callRpc(client, "create_ticket_escalation_policy", {
    p_tenant_id: v.tenantId,
    p_code: v.code,
    p_name: v.name,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function createTicketEscalationPolicyVersion(client: TicketMutationRpcClient, input: CreateTicketEscalationPolicyVersionInput) {
  const v = CreateTicketEscalationPolicyVersionInputSchema.parse(input);
  return callRpc(client, "create_ticket_escalation_policy_version", {
    p_policy_id: v.policyId,
    p_channel: v.channel,
    p_category_id: v.categoryId,
    p_priority: v.priority,
    p_queue_id: v.queueId,
    p_precedence_rank: v.precedenceRank,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function addTicketEscalationLevel(client: TicketMutationRpcClient, input: AddTicketEscalationLevelInput) {
  const v = AddTicketEscalationLevelInputSchema.parse(input);
  return callRpc(client, "add_ticket_escalation_level", {
    p_policy_version_id: v.policyVersionId,
    p_level_number: v.levelNumber,
    p_trigger_type: v.triggerType,
    p_threshold_minutes: v.thresholdMinutes,
    p_min_priority: v.minPriority,
    p_target_type: v.targetType,
    p_target_queue_id: v.targetQueueId,
    p_target_employee_id: v.targetEmployeeId,
    p_action_notify: v.actionNotify,
    p_action_reassign: v.actionReassign,
    p_cooldown_minutes: v.cooldownMinutes,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function publishTicketEscalationPolicyVersion(client: TicketMutationRpcClient, input: PublishTicketEscalationPolicyVersionInput) {
  const v = PublishTicketEscalationPolicyVersionInputSchema.parse(input);
  return callRpc(client, "publish_ticket_escalation_policy_version", {
    p_version_id: v.versionId,
    p_expected_version: v.expectedVersion,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function escalateTicket(client: TicketMutationRpcClient, input: EscalateTicketInput) {
  const v = EscalateTicketInputSchema.parse(input);
  return callRpc(client, "escalate_ticket", {
    p_ticket_id: v.ticketId,
    p_expected_version: v.expectedVersion,
    p_target_type: v.targetType,
    p_target_queue_id: v.targetQueueId,
    p_target_employee_id: v.targetEmployeeId,
    p_reassign: v.reassign,
    p_reason: v.reason,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function acknowledgeTicketEscalation(client: TicketMutationRpcClient, input: AcknowledgeTicketEscalationInput) {
  const v = AcknowledgeTicketEscalationInputSchema.parse(input);
  return callRpc(client, "acknowledge_ticket_escalation", {
    p_ticket_id: v.ticketId,
    p_expected_version: v.expectedVersion,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function resolveTicketEscalation(client: TicketMutationRpcClient, input: ResolveTicketEscalationInput) {
  const v = ResolveTicketEscalationInputSchema.parse(input);
  return callRpc(client, "resolve_ticket_escalation", {
    p_ticket_id: v.ticketId,
    p_expected_version: v.expectedVersion,
    p_reason: v.reason,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function suppressTicketEscalation(client: TicketMutationRpcClient, input: SuppressTicketEscalationInput) {
  const v = SuppressTicketEscalationInputSchema.parse(input);
  return callRpc(client, "suppress_ticket_escalation", {
    p_ticket_id: v.ticketId,
    p_reason: v.reason,
    p_expires_at: v.expiresAt,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function revokeTicketEscalationSuppression(client: TicketMutationRpcClient, input: RevokeTicketEscalationSuppressionInput) {
  const v = RevokeTicketEscalationSuppressionInputSchema.parse(input);
  return callRpc(client, "revoke_ticket_escalation_suppression", {
    p_ticket_id: v.ticketId,
    p_suppression_id: v.suppressionId,
    p_expected_version: v.expectedVersion,
    p_reason: v.reason,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function runTicketEscalationEvaluationBatch(client: TicketMutationRpcClient, input: RunTicketEscalationEvaluationBatchInput) {
  const v = RunTicketEscalationEvaluationBatchInputSchema.parse(input);
  return callRpc(client, "run_ticket_escalation_evaluation_batch", {
    p_tenant_id: v.tenantId,
    p_as_of: v.asOf,
    p_period_label: v.periodLabel,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

// ===========================================================================
// HRT-292 (CG-S12-HRT-020): Typed Ticket-Linked Records.
// ===========================================================================

// app.link_ticket_record raises the anti-enumerating record_not_eligible for
// ANY invalid/unauthorized candidate (forged id, cross-tenant, deleted, or
// merely unauthorized for THIS caller -- indistinguishable by design, C-05).
// A caller wanting a durably-logged denial trail must catch this error and
// separately call recordTicketLinkAccessDenial below, in a NEW request --
// app.link_ticket_record's own RAISE aborts its transaction, so it cannot
// self-log (mirrors app.get_customer_inventory_balance's identical,
// already-established split, ATW-242).
export async function linkTicketRecord(client: TicketMutationRpcClient, input: LinkTicketRecordInput) {
  const v = LinkTicketRecordInputSchema.parse(input);
  return callRpc(client, "link_ticket_record", {
    p_ticket_id: v.ticketId,
    p_entity_type: v.entityType,
    p_entity_id: v.entityId,
    p_relationship: v.relationship,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function unlinkTicketRecord(client: TicketMutationRpcClient, input: UnlinkTicketRecordInput) {
  const v = UnlinkTicketRecordInputSchema.parse(input);
  return callRpc(client, "unlink_ticket_record", {
    p_link_id: v.linkId,
    p_expected_version: v.expectedVersion,
    p_reason: v.reason,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

// The follow-up, always-succeeding audit call a linkTicketRecord() catch
// block should issue (in a fresh request, never inside the same try/catch
// transaction) after a genuine denial -- see app.record_ticket_link_access_
// denial's own comment for why this cannot be folded into link_ticket_
// record itself.
export async function recordTicketLinkAccessDenial(client: TicketMutationRpcClient, input: RecordTicketLinkAccessDenialInput) {
  const v = RecordTicketLinkAccessDenialInputSchema.parse(input);
  return callRpc(client, "record_ticket_link_access_denial", {
    p_tenant_id: v.tenantId,
    p_ticket_id: v.ticketId,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
    p_entity_type: v.entityType,
    p_entity_id: v.entityId,
    p_reason: v.reason,
  });
}

// Fired when a viewer actually expands a summary card or follows a deep
// link -- never on every list render (audit impact "safe-summary/deep-link
// access... audited", never a per-page-view spam source).
export async function recordTicketLinkSummaryAccess(client: TicketMutationRpcClient, input: RecordTicketLinkSummaryAccessInput) {
  const v = RecordTicketLinkSummaryAccessInputSchema.parse(input);
  return callRpc(client, "record_ticket_link_summary_access", {
    p_link_id: v.linkId,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
    p_access_type: v.accessType,
  });
}
