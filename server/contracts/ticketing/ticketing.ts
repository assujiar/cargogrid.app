/**
 * Ticketing contract (HRT-286/287, CG-S12-HRT-014/015) -- the canonical,
 * cross-channel ticket/conversation model's TypeScript surface. Mirrors
 * supabase/migrations/20260731060000_create_ticketing_internal.sql (HRT-286)
 * and 20260731080000_extend_ticketing_customer_channel.sql (HRT-287)'s
 * tables/RPCs. Follows the exact directory convention every prior HRT
 * checkpoint established: Zod schemas here, list/read projections in
 * server/queries/ticketing.ts, RPC-calling mutation wrappers with an
 * enumerated error-code type in server/mutations/ticketing.ts -- one
 * canonical ticket service, HRT-287 extends it with new customer-facing
 * functions alongside the existing internal ones, per this task's own
 * explicit instruction, never a parallel "customer-ticketing" module.
 *
 * Directory/naming choice (HRT-286, confirmed correct by HRT-287): channel is
 * a plain field, never a type discriminant of its own file/module. Customer
 * row/input shapes below (CustomerTicket*, CustomerAccountRow, ...) are their
 * OWN, deliberately narrower types -- never TicketDetail/TicketListRow with
 * fields merely unused client-side, per HRT-287's own "every customer read
 * path needs its own explicit customer-safe projection" business rule.
 */

import { z } from "zod";

export const TICKET_CHANNELS = ["internal", "customer", "helpdesk"] as const;
export const TicketChannelSchema = z.enum(TICKET_CHANNELS);
export type TicketChannel = z.infer<typeof TicketChannelSchema>;

export const TICKET_PRIORITIES = ["low", "normal", "high", "urgent"] as const;
export const TicketPrioritySchema = z.enum(TICKET_PRIORITIES);
export type TicketPriority = z.infer<typeof TicketPrioritySchema>;

export const TICKET_STATUSES = ["new", "open", "pending", "on_hold", "resolved", "closed", "cancelled"] as const;
export const TicketStatusSchema = z.enum(TICKET_STATUSES);
export type TicketStatus = z.infer<typeof TicketStatusSchema>;

export const MESSAGE_VISIBILITIES = ["public", "internal"] as const;
export const MessageVisibilitySchema = z.enum(MESSAGE_VISIBILITIES);
export type MessageVisibility = z.infer<typeof MessageVisibilitySchema>;

export const MESSAGE_AUTHOR_ROLES = ["requester", "staff"] as const;
export const MessageAuthorRoleSchema = z.enum(MESSAGE_AUTHOR_ROLES);
export type MessageAuthorRole = z.infer<typeof MessageAuthorRoleSchema>;

export const TICKET_EVENT_TYPES = [
  "create",
  "status_change",
  "assignment",
  "queue_transfer",
  "classification_change",
  "watcher_added",
  "watcher_removed",
  "message_redacted",
  "support_grant_linked",
] as const;
export const TicketEventTypeSchema = z.enum(TICKET_EVENT_TYPES);
export type TicketEventType = z.infer<typeof TicketEventTypeSchema>;

// --- HRT-288 (CG-S12-HRT-016): helpdesk-only metadata enums. ---

export const HELPDESK_SEVERITIES = ["low", "medium", "high", "critical"] as const;
export const HelpdeskSeveritySchema = z.enum(HELPDESK_SEVERITIES);
export type HelpdeskSeverity = z.infer<typeof HelpdeskSeveritySchema>;

export const HELPDESK_ENVIRONMENTS = ["production", "staging", "sandbox", "other"] as const;
export const HelpdeskEnvironmentSchema = z.enum(HELPDESK_ENVIRONMENTS);
export type HelpdeskEnvironment = z.infer<typeof HelpdeskEnvironmentSchema>;

// --- Core rows ---

export const TicketQueueRowSchema = z.object({
  id: z.string().uuid(),
  orgUnitId: z.string().uuid(),
  code: z.string(),
  name: z.string(),
  description: z.string().nullable(),
  status: z.enum(["active", "inactive"]),
  recordVersion: z.number().int().positive(),
});
export type TicketQueueRow = z.infer<typeof TicketQueueRowSchema>;

export function parseTicketQueueRow(row: Record<string, unknown>): TicketQueueRow {
  return TicketQueueRowSchema.parse({
    id: row.id,
    orgUnitId: row.org_unit_id,
    code: row.code,
    name: row.name,
    description: row.description ?? null,
    status: row.status,
    recordVersion: row.record_version,
  });
}

export const TicketCategoryRowSchema = z.object({
  id: z.string().uuid(),
  code: z.string(),
  name: z.string(),
  defaultQueueId: z.string().uuid().nullable(),
  customerVisible: z.boolean(),
  helpdeskVisible: z.boolean(),
  status: z.enum(["active", "inactive"]),
  recordVersion: z.number().int().positive(),
});
export type TicketCategoryRow = z.infer<typeof TicketCategoryRowSchema>;

export function parseTicketCategoryRow(row: Record<string, unknown>): TicketCategoryRow {
  return TicketCategoryRowSchema.parse({
    id: row.id,
    code: row.code,
    name: row.name,
    defaultQueueId: row.default_queue_id ?? null,
    customerVisible: row.customer_visible ?? false,
    helpdeskVisible: row.helpdesk_visible ?? false,
    status: row.status,
    recordVersion: row.record_version,
  });
}

export const TicketQueueMemberRowSchema = z.object({
  id: z.string().uuid(),
  queueId: z.string().uuid(),
  employeeId: z.string().uuid(),
  employeeName: z.string(),
  status: z.enum(["active", "removed"]),
  addedBy: z.string().nullable(),
  addedAt: z.string(),
  recordVersion: z.number().int().positive(),
});
export type TicketQueueMemberRow = z.infer<typeof TicketQueueMemberRowSchema>;

export function parseTicketQueueMemberRow(row: Record<string, unknown>): TicketQueueMemberRow {
  return TicketQueueMemberRowSchema.parse({
    id: row.id,
    queueId: row.queue_id,
    employeeId: row.employee_id,
    employeeName: row.employee_name,
    status: row.status,
    addedBy: row.added_by ?? null,
    addedAt: row.added_at,
    recordVersion: row.record_version,
  });
}

export const TicketListRowSchema = z.object({
  id: z.string().uuid(),
  ticketNumber: z.string(),
  subject: z.string(),
  status: TicketStatusSchema,
  priority: TicketPrioritySchema,
  categoryCode: z.string(),
  queueCode: z.string(),
  requesterEmployeeId: z.string().uuid().nullable(),
  requesterCustomerAccountId: z.string().uuid().nullable(),
  requesterName: z.string().nullable(),
  assigneeEmployeeId: z.string().uuid().nullable(),
  assigneeName: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type TicketListRow = z.infer<typeof TicketListRowSchema>;

export function parseTicketListRow(row: Record<string, unknown>): TicketListRow {
  return TicketListRowSchema.parse({
    id: row.id,
    ticketNumber: row.ticket_number,
    subject: row.subject,
    status: row.status,
    priority: row.priority,
    categoryCode: row.category_code,
    queueCode: row.queue_code,
    requesterEmployeeId: row.requester_employee_id ?? null,
    requesterCustomerAccountId: row.requester_customer_account_id ?? null,
    requesterName: row.requester_name ?? null,
    assigneeEmployeeId: row.assignee_employee_id ?? null,
    assigneeName: row.assignee_name ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const MyTicketListRowSchema = z.object({
  id: z.string().uuid(),
  ticketNumber: z.string(),
  subject: z.string(),
  status: TicketStatusSchema,
  priority: TicketPrioritySchema,
  categoryCode: z.string(),
  queueCode: z.string(),
  assigneeEmployeeId: z.string().uuid().nullable(),
  assigneeName: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type MyTicketListRow = z.infer<typeof MyTicketListRowSchema>;

export function parseMyTicketListRow(row: Record<string, unknown>): MyTicketListRow {
  return MyTicketListRowSchema.parse({
    id: row.id,
    ticketNumber: row.ticket_number,
    subject: row.subject,
    status: row.status,
    priority: row.priority,
    categoryCode: row.category_code,
    queueCode: row.queue_code,
    assigneeEmployeeId: row.assignee_employee_id ?? null,
    assigneeName: row.assignee_name ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const TicketDetailSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  ticketNumber: z.string(),
  channel: TicketChannelSchema,
  categoryId: z.string().uuid(),
  categoryCode: z.string(),
  categoryName: z.string(),
  queueId: z.string().uuid(),
  queueCode: z.string(),
  queueName: z.string(),
  priority: TicketPrioritySchema,
  subject: z.string(),
  status: TicketStatusSchema,
  requesterEmployeeId: z.string().uuid().nullable(),
  requesterCustomerAccountId: z.string().uuid().nullable(),
  requesterName: z.string().nullable(),
  requestedByAuthUserId: z.string().uuid(),
  requestedBy: z.string().nullable(),
  assigneeEmployeeId: z.string().uuid().nullable(),
  assigneeName: z.string().nullable(),
  assignedAt: z.string().nullable(),
  resolutionSummary: z.string().nullable(),
  resolvedAt: z.string().nullable(),
  closedAt: z.string().nullable(),
  cancelledReason: z.string().nullable(),
  cancelledAt: z.string().nullable(),
  reopenCount: z.number().int().nonnegative(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
  isStaffViewer: z.boolean(),
  isRequesterViewer: z.boolean(),
});
export type TicketDetail = z.infer<typeof TicketDetailSchema>;

export function parseTicketDetail(row: Record<string, unknown>): TicketDetail {
  return TicketDetailSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    ticketNumber: row.ticket_number,
    channel: row.channel,
    categoryId: row.category_id,
    categoryCode: row.category_code,
    categoryName: row.category_name,
    queueId: row.queue_id,
    queueCode: row.queue_code,
    queueName: row.queue_name,
    priority: row.priority,
    subject: row.subject,
    status: row.status,
    requesterEmployeeId: row.requester_employee_id ?? null,
    requesterCustomerAccountId: row.requester_customer_account_id ?? null,
    requesterName: row.requester_name ?? null,
    requestedByAuthUserId: row.requested_by_auth_user_id,
    requestedBy: row.requested_by ?? null,
    assigneeEmployeeId: row.assignee_employee_id ?? null,
    assigneeName: row.assignee_name ?? null,
    assignedAt: row.assigned_at ?? null,
    resolutionSummary: row.resolution_summary ?? null,
    resolvedAt: row.resolved_at ?? null,
    closedAt: row.closed_at ?? null,
    cancelledReason: row.cancelled_reason ?? null,
    cancelledAt: row.cancelled_at ?? null,
    reopenCount: row.reopen_count,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    isStaffViewer: row.is_staff_viewer,
    isRequesterViewer: row.is_requester_viewer,
  });
}

export const TicketMessageRowSchema = z.object({
  id: z.string().uuid(),
  ticketId: z.string().uuid(),
  visibility: MessageVisibilitySchema,
  body: z.string(),
  isRedacted: z.boolean(),
  attachmentFileIds: z.array(z.string().uuid()),
  authorAuthUserId: z.string().uuid(),
  authorLabel: z.string().nullable(),
  authorRole: MessageAuthorRoleSchema,
  createdAt: z.string(),
  recordVersion: z.number().int().positive(),
});
export type TicketMessageRow = z.infer<typeof TicketMessageRowSchema>;

export function parseTicketMessageRow(row: Record<string, unknown>): TicketMessageRow {
  return TicketMessageRowSchema.parse({
    id: row.id,
    ticketId: row.ticket_id,
    visibility: row.visibility,
    body: row.body,
    isRedacted: row.is_redacted,
    attachmentFileIds: row.attachment_file_ids ?? [],
    authorAuthUserId: row.author_auth_user_id,
    authorLabel: row.author_label ?? null,
    authorRole: row.author_role,
    createdAt: row.created_at,
    recordVersion: row.record_version,
  });
}

export const TicketWatcherRowSchema = z.object({
  id: z.string().uuid(),
  ticketId: z.string().uuid(),
  employeeId: z.string().uuid(),
  employeeName: z.string(),
  status: z.enum(["active", "removed"]),
  addedBy: z.string().nullable(),
  addedAt: z.string(),
  recordVersion: z.number().int().positive(),
});
export type TicketWatcherRow = z.infer<typeof TicketWatcherRowSchema>;

export function parseTicketWatcherRow(row: Record<string, unknown>): TicketWatcherRow {
  return TicketWatcherRowSchema.parse({
    id: row.id,
    ticketId: row.ticket_id,
    employeeId: row.employee_id,
    employeeName: row.employee_name,
    status: row.status,
    addedBy: row.added_by ?? null,
    addedAt: row.added_at,
    recordVersion: row.record_version,
  });
}

export const TicketEventRowSchema = z.object({
  id: z.string().uuid(),
  ticketId: z.string().uuid(),
  eventType: TicketEventTypeSchema,
  fromValue: z.string().nullable(),
  toValue: z.string().nullable(),
  reason: z.string().nullable(),
  actorAuthUserId: z.string().uuid().nullable(),
  actorLabel: z.string().nullable(),
  occurredAt: z.string(),
});
export type TicketEventRow = z.infer<typeof TicketEventRowSchema>;

export function parseTicketEventRow(row: Record<string, unknown>): TicketEventRow {
  return TicketEventRowSchema.parse({
    id: row.id,
    ticketId: row.ticket_id,
    eventType: row.event_type,
    fromValue: row.from_value ?? null,
    toValue: row.to_value ?? null,
    reason: row.reason ?? null,
    actorAuthUserId: row.actor_auth_user_id ?? null,
    actorLabel: row.actor_label ?? null,
    occurredAt: row.occurred_at,
  });
}

export const TicketExportRowSchema = z.object({
  ticketNumber: z.string(),
  subject: z.string(),
  status: TicketStatusSchema,
  priority: TicketPrioritySchema,
  categoryCode: z.string(),
  queueCode: z.string(),
  requesterName: z.string().nullable(),
  assigneeName: z.string().nullable(),
  createdAt: z.string(),
  resolvedAt: z.string().nullable(),
  closedAt: z.string().nullable(),
});
export type TicketExportRow = z.infer<typeof TicketExportRowSchema>;

export function parseTicketExportRow(row: Record<string, unknown>): TicketExportRow {
  return TicketExportRowSchema.parse({
    ticketNumber: row.ticket_number,
    subject: row.subject,
    status: row.status,
    priority: row.priority,
    categoryCode: row.category_code,
    queueCode: row.queue_code,
    requesterName: row.requester_name ?? null,
    assigneeName: row.assignee_name ?? null,
    createdAt: row.created_at,
    resolvedAt: row.resolved_at ?? null,
    closedAt: row.closed_at ?? null,
  });
}

// --- Mutation inputs ---

export const CreateTicketQueueInputSchema = z.object({
  tenantId: z.string().uuid(),
  orgUnitId: z.string().uuid(),
  code: z.string().min(1),
  name: z.string().min(1),
  description: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateTicketQueueInput = z.infer<typeof CreateTicketQueueInputSchema>;

export const CreateTicketCategoryInputSchema = z.object({
  tenantId: z.string().uuid(),
  code: z.string().min(1),
  name: z.string().min(1),
  defaultQueueId: z.string().uuid().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateTicketCategoryInput = z.infer<typeof CreateTicketCategoryInputSchema>;

export const AddTicketQueueMemberInputSchema = z.object({
  queueId: z.string().uuid(),
  employeeId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type AddTicketQueueMemberInput = z.infer<typeof AddTicketQueueMemberInputSchema>;

export const RemoveTicketQueueMemberInputSchema = z.object({
  memberId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RemoveTicketQueueMemberInput = z.infer<typeof RemoveTicketQueueMemberInputSchema>;

export const CreateTicketInputSchema = z.object({
  tenantId: z.string().uuid(),
  categoryId: z.string().uuid(),
  queueId: z.string().uuid().nullable(),
  priority: TicketPrioritySchema,
  subject: z.string().min(1),
  body: z.string().min(1),
  idempotencyKey: z.string().min(1).nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateTicketInput = z.infer<typeof CreateTicketInputSchema>;

export const CreateTicketForEmployeeInputSchema = CreateTicketInputSchema.extend({
  requesterEmployeeId: z.string().uuid(),
});
export type CreateTicketForEmployeeInput = z.infer<typeof CreateTicketForEmployeeInputSchema>;

export const ReplyToTicketInputSchema = z.object({
  ticketId: z.string().uuid(),
  body: z.string().min(1),
  visibility: MessageVisibilitySchema,
  attachmentFileIds: z.array(z.string().uuid()).nullable(),
  idempotencyKey: z.string().min(1).nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ReplyToTicketInput = z.infer<typeof ReplyToTicketInputSchema>;

export const RedactTicketMessageInputSchema = z.object({
  messageId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RedactTicketMessageInput = z.infer<typeof RedactTicketMessageInputSchema>;

export const AddTicketWatcherInputSchema = z.object({
  ticketId: z.string().uuid(),
  employeeId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type AddTicketWatcherInput = z.infer<typeof AddTicketWatcherInputSchema>;

export const RemoveTicketWatcherInputSchema = z.object({
  watcherId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RemoveTicketWatcherInput = z.infer<typeof RemoveTicketWatcherInputSchema>;

export const AssignTicketInputSchema = z.object({
  ticketId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  assigneeEmployeeId: z.string().uuid().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type AssignTicketInput = z.infer<typeof AssignTicketInputSchema>;

export const TransferTicketQueueInputSchema = z.object({
  ticketId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  newQueueId: z.string().uuid(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type TransferTicketQueueInput = z.infer<typeof TransferTicketQueueInputSchema>;

export const UpdateTicketClassificationInputSchema = z.object({
  ticketId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  categoryId: z.string().uuid(),
  priority: TicketPrioritySchema,
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type UpdateTicketClassificationInput = z.infer<typeof UpdateTicketClassificationInputSchema>;

export const TransitionTicketStatusInputSchema = z.object({
  ticketId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  toStatus: TicketStatusSchema,
  reason: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type TransitionTicketStatusInput = z.infer<typeof TransitionTicketStatusInputSchema>;

export const SetTicketCategoryCustomerVisibilityInputSchema = z.object({
  categoryId: z.string().uuid(),
  customerVisible: z.boolean(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type SetTicketCategoryCustomerVisibilityInput = z.infer<typeof SetTicketCategoryCustomerVisibilityInputSchema>;

// --- HRT-287 (CG-S12-HRT-015): Layer 4 customer-facing rows/inputs. Each is
// its own, deliberately narrower shape than its internal-channel sibling --
// never TicketDetail/TicketListRow reused with fields merely unused
// client-side (business rule, section 24). No queue/assignee identity, no
// internal-note/event exposure anywhere in this section.

export const CustomerAccountRowSchema = z.object({
  accountId: z.string().uuid(),
  legalName: z.string(),
  parentAccountId: z.string().uuid().nullable(),
});
export type CustomerAccountRow = z.infer<typeof CustomerAccountRowSchema>;

export function parseCustomerAccountRow(row: Record<string, unknown>): CustomerAccountRow {
  return CustomerAccountRowSchema.parse({
    accountId: row.account_id,
    legalName: row.legal_name,
    parentAccountId: row.parent_account_id ?? null,
  });
}

export const CustomerTicketCategoryRowSchema = z.object({
  id: z.string().uuid(),
  code: z.string(),
  name: z.string(),
});
export type CustomerTicketCategoryRow = z.infer<typeof CustomerTicketCategoryRowSchema>;

export function parseCustomerTicketCategoryRow(row: Record<string, unknown>): CustomerTicketCategoryRow {
  return CustomerTicketCategoryRowSchema.parse({
    id: row.id,
    code: row.code,
    name: row.name,
  });
}

export const CustomerTicketListRowSchema = z.object({
  id: z.string().uuid(),
  ticketNumber: z.string(),
  subject: z.string(),
  status: TicketStatusSchema,
  priority: TicketPrioritySchema,
  categoryName: z.string(),
  accountId: z.string().uuid(),
  accountName: z.string(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type CustomerTicketListRow = z.infer<typeof CustomerTicketListRowSchema>;

export function parseCustomerTicketListRow(row: Record<string, unknown>): CustomerTicketListRow {
  return CustomerTicketListRowSchema.parse({
    id: row.id,
    ticketNumber: row.ticket_number,
    subject: row.subject,
    status: row.status,
    priority: row.priority,
    categoryName: row.category_name,
    accountId: row.account_id,
    accountName: row.account_name,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const CustomerTicketDetailSchema = z.object({
  id: z.string().uuid(),
  ticketNumber: z.string(),
  subject: z.string(),
  status: TicketStatusSchema,
  priority: TicketPrioritySchema,
  categoryName: z.string(),
  accountId: z.string().uuid(),
  accountName: z.string(),
  resolutionSummary: z.string().nullable(),
  cancelledReason: z.string().nullable(),
  lastReopenReason: z.string().nullable(),
  reopenCount: z.number().int().nonnegative(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
  resolvedAt: z.string().nullable(),
  closedAt: z.string().nullable(),
});
export type CustomerTicketDetail = z.infer<typeof CustomerTicketDetailSchema>;

export function parseCustomerTicketDetail(row: Record<string, unknown>): CustomerTicketDetail {
  return CustomerTicketDetailSchema.parse({
    id: row.id,
    ticketNumber: row.ticket_number,
    subject: row.subject,
    status: row.status,
    priority: row.priority,
    categoryName: row.category_name,
    accountId: row.account_id,
    accountName: row.account_name,
    resolutionSummary: row.resolution_summary ?? null,
    cancelledReason: row.cancelled_reason ?? null,
    lastReopenReason: row.last_reopen_reason ?? null,
    reopenCount: row.reopen_count,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    resolvedAt: row.resolved_at ?? null,
    closedAt: row.closed_at ?? null,
  });
}

export const CUSTOMER_MESSAGE_AUTHOR_ROLES = ["requester", "staff"] as const;
export const CustomerMessageAuthorRoleSchema = z.enum(CUSTOMER_MESSAGE_AUTHOR_ROLES);

export const CustomerTicketMessageRowSchema = z.object({
  id: z.string().uuid(),
  ticketId: z.string().uuid(),
  body: z.string(),
  isRedacted: z.boolean(),
  attachmentFileIds: z.array(z.string().uuid()),
  authorRole: CustomerMessageAuthorRoleSchema,
  authorDisplay: z.string(),
  createdAt: z.string(),
  recordVersion: z.number().int().positive(),
});
export type CustomerTicketMessageRow = z.infer<typeof CustomerTicketMessageRowSchema>;

export function parseCustomerTicketMessageRow(row: Record<string, unknown>): CustomerTicketMessageRow {
  return CustomerTicketMessageRowSchema.parse({
    id: row.id,
    ticketId: row.ticket_id,
    body: row.body,
    isRedacted: row.is_redacted,
    attachmentFileIds: row.attachment_file_ids ?? [],
    authorRole: row.author_role,
    authorDisplay: row.author_display,
    createdAt: row.created_at,
    recordVersion: row.record_version,
  });
}

// --- HRT-287 customer mutation inputs ---

export const CreateCustomerTicketInputSchema = z.object({
  tenantId: z.string().uuid(),
  accountId: z.string().uuid(),
  categoryId: z.string().uuid(),
  priority: TicketPrioritySchema,
  subject: z.string().min(1),
  body: z.string().min(1),
  idempotencyKey: z.string().min(1).nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateCustomerTicketInput = z.infer<typeof CreateCustomerTicketInputSchema>;

export const ReplyToCustomerTicketInputSchema = z.object({
  ticketId: z.string().uuid(),
  body: z.string().min(1),
  attachmentFileIds: z.array(z.string().uuid()).nullable(),
  idempotencyKey: z.string().min(1).nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ReplyToCustomerTicketInput = z.infer<typeof ReplyToCustomerTicketInputSchema>;

// --- HRT-288 (CG-S12-HRT-016): tenant-to-CargoGrid helpdesk rows/inputs.
// Third founding channel -- the "requester" is the tenant itself (never a
// specific employee/account row), "staff" is CargoGrid Platform support
// (Supreme Admin only, this prompt's own disclosed bounded-scope decision).
// Tenant-safe rows below are their own, deliberately narrow shapes (no
// support_queue/assignee/support_access_case_ref exposure), mirroring the
// customer channel's "every read path needs its own explicit safe
// projection" discipline exactly. Platform-side (Supreme-Admin-facing) rows
// are a SEPARATE, richer shape -- never reused for the tenant side.

export const HelpdeskTicketCategoryRowSchema = z.object({
  id: z.string().uuid(),
  code: z.string(),
  name: z.string(),
});
export type HelpdeskTicketCategoryRow = z.infer<typeof HelpdeskTicketCategoryRowSchema>;

export function parseHelpdeskTicketCategoryRow(row: Record<string, unknown>): HelpdeskTicketCategoryRow {
  return HelpdeskTicketCategoryRowSchema.parse({
    id: row.id,
    code: row.code,
    name: row.name,
  });
}

export const HelpdeskTicketListRowSchema = z.object({
  id: z.string().uuid(),
  ticketNumber: z.string(),
  subject: z.string(),
  status: TicketStatusSchema,
  priority: TicketPrioritySchema,
  severity: HelpdeskSeveritySchema.nullable(),
  categoryName: z.string(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type HelpdeskTicketListRow = z.infer<typeof HelpdeskTicketListRowSchema>;

export function parseHelpdeskTicketListRow(row: Record<string, unknown>): HelpdeskTicketListRow {
  return HelpdeskTicketListRowSchema.parse({
    id: row.id,
    ticketNumber: row.ticket_number,
    subject: row.subject,
    status: row.status,
    priority: row.priority,
    severity: row.severity ?? null,
    categoryName: row.category_name,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const HelpdeskTicketDetailSchema = z.object({
  id: z.string().uuid(),
  ticketNumber: z.string(),
  subject: z.string(),
  status: TicketStatusSchema,
  priority: TicketPrioritySchema,
  severity: HelpdeskSeveritySchema.nullable(),
  productArea: z.string().nullable(),
  environment: HelpdeskEnvironmentSchema.nullable(),
  externalReference: z.string().nullable(),
  categoryName: z.string(),
  resolutionSummary: z.string().nullable(),
  cancelledReason: z.string().nullable(),
  lastReopenReason: z.string().nullable(),
  reopenCount: z.number().int().nonnegative(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
  resolvedAt: z.string().nullable(),
  closedAt: z.string().nullable(),
});
export type HelpdeskTicketDetail = z.infer<typeof HelpdeskTicketDetailSchema>;

export function parseHelpdeskTicketDetail(row: Record<string, unknown>): HelpdeskTicketDetail {
  return HelpdeskTicketDetailSchema.parse({
    id: row.id,
    ticketNumber: row.ticket_number,
    subject: row.subject,
    status: row.status,
    priority: row.priority,
    severity: row.severity ?? null,
    productArea: row.product_area ?? null,
    environment: row.environment ?? null,
    externalReference: row.external_reference ?? null,
    categoryName: row.category_name,
    resolutionSummary: row.resolution_summary ?? null,
    cancelledReason: row.cancelled_reason ?? null,
    lastReopenReason: row.last_reopen_reason ?? null,
    reopenCount: row.reopen_count,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    resolvedAt: row.resolved_at ?? null,
    closedAt: row.closed_at ?? null,
  });
}

export const HELPDESK_MESSAGE_AUTHOR_ROLES = ["requester", "staff"] as const;
export const HelpdeskMessageAuthorRoleSchema = z.enum(HELPDESK_MESSAGE_AUTHOR_ROLES);

export const HelpdeskTicketMessageRowSchema = z.object({
  id: z.string().uuid(),
  ticketId: z.string().uuid(),
  body: z.string(),
  isRedacted: z.boolean(),
  attachmentFileIds: z.array(z.string().uuid()),
  authorRole: HelpdeskMessageAuthorRoleSchema,
  authorDisplay: z.string(),
  createdAt: z.string(),
  recordVersion: z.number().int().positive(),
});
export type HelpdeskTicketMessageRow = z.infer<typeof HelpdeskTicketMessageRowSchema>;

export function parseHelpdeskTicketMessageRow(row: Record<string, unknown>): HelpdeskTicketMessageRow {
  return HelpdeskTicketMessageRowSchema.parse({
    id: row.id,
    ticketId: row.ticket_id,
    body: row.body,
    isRedacted: row.is_redacted,
    attachmentFileIds: row.attachment_file_ids ?? [],
    authorRole: row.author_role,
    authorDisplay: row.author_display,
    createdAt: row.created_at,
    recordVersion: row.record_version,
  });
}

// --- Platform-side (Supreme-Admin-facing) helpdesk rows -- a genuinely
// separate, cross-tenant-capable, richer shape. Never reused for the
// tenant-safe rows above. ---

export const SupportQueueRowSchema = z.object({
  id: z.string().uuid(),
  code: z.string(),
  name: z.string(),
  description: z.string().nullable(),
  status: z.enum(["active", "inactive"]),
  recordVersion: z.number().int().positive(),
});
export type SupportQueueRow = z.infer<typeof SupportQueueRowSchema>;

export function parseSupportQueueRow(row: Record<string, unknown>): SupportQueueRow {
  return SupportQueueRowSchema.parse({
    id: row.id,
    code: row.code,
    name: row.name,
    description: row.description ?? null,
    status: row.status,
    recordVersion: row.record_version,
  });
}

export const PlatformHelpdeskTicketListRowSchema = z.object({
  id: z.string().uuid(),
  ticketNumber: z.string(),
  tenantId: z.string().uuid(),
  tenantName: z.string(),
  subject: z.string(),
  status: TicketStatusSchema,
  priority: TicketPrioritySchema,
  severity: HelpdeskSeveritySchema.nullable(),
  productArea: z.string().nullable(),
  supportQueueId: z.string().uuid().nullable(),
  supportQueueCode: z.string().nullable(),
  assigneeSupportAuthUserId: z.string().uuid().nullable(),
  assigneeEmail: z.string().nullable(),
  supportAccessCaseRef: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type PlatformHelpdeskTicketListRow = z.infer<typeof PlatformHelpdeskTicketListRowSchema>;

export function parsePlatformHelpdeskTicketListRow(row: Record<string, unknown>): PlatformHelpdeskTicketListRow {
  return PlatformHelpdeskTicketListRowSchema.parse({
    id: row.id,
    ticketNumber: row.ticket_number,
    tenantId: row.tenant_id,
    tenantName: row.tenant_name,
    subject: row.subject,
    status: row.status,
    priority: row.priority,
    severity: row.severity ?? null,
    productArea: row.product_area ?? null,
    supportQueueId: row.support_queue_id ?? null,
    supportQueueCode: row.support_queue_code ?? null,
    assigneeSupportAuthUserId: row.assignee_support_auth_user_id ?? null,
    assigneeEmail: row.assignee_email ?? null,
    supportAccessCaseRef: row.support_access_case_ref ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const PlatformHelpdeskTicketDetailSchema = z.object({
  id: z.string().uuid(),
  ticketNumber: z.string(),
  tenantId: z.string().uuid(),
  tenantName: z.string(),
  subject: z.string(),
  status: TicketStatusSchema,
  priority: TicketPrioritySchema,
  severity: HelpdeskSeveritySchema.nullable(),
  productArea: z.string().nullable(),
  environment: HelpdeskEnvironmentSchema.nullable(),
  externalReference: z.string().nullable(),
  categoryName: z.string(),
  supportQueueId: z.string().uuid().nullable(),
  supportQueueCode: z.string().nullable(),
  assigneeSupportAuthUserId: z.string().uuid().nullable(),
  assigneeEmail: z.string().nullable(),
  supportAccessCaseRef: z.string().nullable(),
  supportGrantStatus: z.string().nullable(),
  supportGrantExpiresAt: z.string().nullable(),
  supportGrantRevokedAt: z.string().nullable(),
  resolutionSummary: z.string().nullable(),
  cancelledReason: z.string().nullable(),
  lastReopenReason: z.string().nullable(),
  reopenCount: z.number().int().nonnegative(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
  resolvedAt: z.string().nullable(),
  closedAt: z.string().nullable(),
});
export type PlatformHelpdeskTicketDetail = z.infer<typeof PlatformHelpdeskTicketDetailSchema>;

export function parsePlatformHelpdeskTicketDetail(row: Record<string, unknown>): PlatformHelpdeskTicketDetail {
  return PlatformHelpdeskTicketDetailSchema.parse({
    id: row.id,
    ticketNumber: row.ticket_number,
    tenantId: row.tenant_id,
    tenantName: row.tenant_name,
    subject: row.subject,
    status: row.status,
    priority: row.priority,
    severity: row.severity ?? null,
    productArea: row.product_area ?? null,
    environment: row.environment ?? null,
    externalReference: row.external_reference ?? null,
    categoryName: row.category_name,
    supportQueueId: row.support_queue_id ?? null,
    supportQueueCode: row.support_queue_code ?? null,
    assigneeSupportAuthUserId: row.assignee_support_auth_user_id ?? null,
    assigneeEmail: row.assignee_email ?? null,
    supportAccessCaseRef: row.support_access_case_ref ?? null,
    supportGrantStatus: row.support_grant_status ?? null,
    supportGrantExpiresAt: row.support_grant_expires_at ?? null,
    supportGrantRevokedAt: row.support_grant_revoked_at ?? null,
    resolutionSummary: row.resolution_summary ?? null,
    cancelledReason: row.cancelled_reason ?? null,
    lastReopenReason: row.last_reopen_reason ?? null,
    reopenCount: row.reopen_count,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    resolvedAt: row.resolved_at ?? null,
    closedAt: row.closed_at ?? null,
  });
}

// --- HRT-288 helpdesk mutation inputs ---

export const CreateHelpdeskTicketInputSchema = z.object({
  tenantId: z.string().uuid(),
  categoryId: z.string().uuid(),
  priority: TicketPrioritySchema,
  severity: HelpdeskSeveritySchema.nullable(),
  productArea: z.string().nullable(),
  environment: HelpdeskEnvironmentSchema.nullable(),
  externalReference: z.string().nullable(),
  subject: z.string().min(1),
  body: z.string().min(1),
  idempotencyKey: z.string().min(1).nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateHelpdeskTicketInput = z.infer<typeof CreateHelpdeskTicketInputSchema>;

export const ReplyToHelpdeskTicketInputSchema = z.object({
  ticketId: z.string().uuid(),
  body: z.string().min(1),
  attachmentFileIds: z.array(z.string().uuid()).nullable(),
  idempotencyKey: z.string().min(1).nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ReplyToHelpdeskTicketInput = z.infer<typeof ReplyToHelpdeskTicketInputSchema>;

export const SetTicketCategoryHelpdeskVisibilityInputSchema = z.object({
  categoryId: z.string().uuid(),
  helpdeskVisible: z.boolean(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type SetTicketCategoryHelpdeskVisibilityInput = z.infer<typeof SetTicketCategoryHelpdeskVisibilityInputSchema>;

export const CreateSupportQueueInputSchema = z.object({
  code: z.string().min(1),
  name: z.string().min(1),
  description: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateSupportQueueInput = z.infer<typeof CreateSupportQueueInputSchema>;

export const AssignHelpdeskTicketInputSchema = z.object({
  ticketId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  assigneeAuthUserId: z.string().uuid().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type AssignHelpdeskTicketInput = z.infer<typeof AssignHelpdeskTicketInputSchema>;

export const TransferHelpdeskSupportQueueInputSchema = z.object({
  ticketId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  newSupportQueueId: z.string().uuid(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type TransferHelpdeskSupportQueueInput = z.infer<typeof TransferHelpdeskSupportQueueInputSchema>;

export const UpdateHelpdeskTicketClassificationInputSchema = z.object({
  ticketId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  categoryId: z.string().uuid(),
  priority: TicketPrioritySchema,
  severity: HelpdeskSeveritySchema.nullable(),
  productArea: z.string().nullable(),
  environment: HelpdeskEnvironmentSchema.nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type UpdateHelpdeskTicketClassificationInput = z.infer<typeof UpdateHelpdeskTicketClassificationInputSchema>;

export const LinkHelpdeskSupportGrantInputSchema = z.object({
  ticketId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  caseRef: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type LinkHelpdeskSupportGrantInput = z.infer<typeof LinkHelpdeskSupportGrantInputSchema>;
