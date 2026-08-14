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
