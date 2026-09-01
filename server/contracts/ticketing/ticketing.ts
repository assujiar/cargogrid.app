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
import { ClassificationSchema } from "../document/document.ts";

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

/**
 * ISS-2026-087: app.initiate_ticket_attachment_upload (20260901120000) --
 * one file per call, mirroring server/contracts/employee/employee.ts's own
 * InitiateEmployeeDocumentUploadInputSchema shape exactly. `attachmentFileIds`
 * on ReplyToTicketInputSchema above is genuinely plural (a support
 * conversation routinely needs more than one file per reply, per
 * 20260731060000's own decision 8) -- the calling Server Action uploads each
 * selected file with its own call to this RPC first, collecting the
 * resulting file ids, then passes the full array into replyToTicket.
 */
export const InitiateTicketAttachmentUploadInputSchema = z.object({
  ticketId: z.string().uuid(),
  originalFilename: z.string().min(1),
  mimeType: z.string().min(1),
  sizeBytes: z.number().int().positive(),
  classification: ClassificationSchema.nullable().default(null),
  idempotencyKey: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type InitiateTicketAttachmentUploadInput = z.input<typeof InitiateTicketAttachmentUploadInputSchema>;

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
  // HRT-290 (CG-S12-HRT-018): two new, optional, DEFAULTed trailing fields --
  // mirrors the migration's own explicit drop+create widening of
  // app.assign_ticket (never a bare create or replace, which cannot add a
  // parameter to an existing signature without leaving a stale second
  // overload behind). Every pre-existing caller of this input type is
  // unaffected -- both fields are optional here too.
  reason: z.string().nullable().optional(),
  overrideWorkloadLimit: z.boolean().optional(),
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

// ===========================================================================
// HRT-289 (CG-S12-HRT-017): SLA -- tightly ticket-coupled (every SLA row
// scopes off channel/category/priority/queue/support_queue and every clock
// is 1:1 with a ticket), so it extends THIS module rather than a sibling
// one -- documented per this task's own explicit "your call, document it"
// instruction. Mirrors supabase/migrations/20260731120000_create_ticket_sla.sql.
// The Knowledge Base half (genuinely standalone -- an article has no
// required ticket relationship) instead lives in its own sibling module,
// server/contracts/knowledge-base/knowledge-base.ts.
// ===========================================================================

export const SLA_CLOCK_STATUSES = ["running", "paused", "completed", "cancelled"] as const;
export const SlaClockStatusSchema = z.enum(SLA_CLOCK_STATUSES);
export type SlaClockStatus = z.infer<typeof SlaClockStatusSchema>;

export const SLA_PHASE_STATUSES = ["pending", "met", "breached"] as const;
export const SlaPhaseStatusSchema = z.enum(SLA_PHASE_STATUSES);
export type SlaPhaseStatus = z.infer<typeof SlaPhaseStatusSchema>;

export const SLA_PAUSE_REASON_CODES = ["waiting_on_customer", "waiting_on_third_party", "internal_investigation", "other"] as const;
export const SlaPauseReasonCodeSchema = z.enum(SLA_PAUSE_REASON_CODES);
export type SlaPauseReasonCode = z.infer<typeof SlaPauseReasonCodeSchema>;

export const SlaCalendarRowSchema = z.object({
  id: z.string().uuid(),
  code: z.string(),
  name: z.string(),
  status: z.enum(["active", "inactive"]),
  recordVersion: z.number().int().positive(),
});
export type SlaCalendarRow = z.infer<typeof SlaCalendarRowSchema>;

export function parseSlaCalendarRow(row: Record<string, unknown>): SlaCalendarRow {
  return SlaCalendarRowSchema.parse({
    id: row.id,
    code: row.code,
    name: row.name,
    status: row.status,
    recordVersion: row.record_version,
  });
}

export const SlaCalendarVersionRowSchema = z.object({
  id: z.string().uuid(),
  versionNumber: z.number().int().positive(),
  status: z.enum(["draft", "published", "superseded"]),
  timezone: z.string(),
  is24x7: z.boolean(),
  publishedAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
});
export type SlaCalendarVersionRow = z.infer<typeof SlaCalendarVersionRowSchema>;

export function parseSlaCalendarVersionRow(row: Record<string, unknown>): SlaCalendarVersionRow {
  return SlaCalendarVersionRowSchema.parse({
    id: row.id,
    versionNumber: row.version_number,
    status: row.status,
    timezone: row.timezone,
    is24x7: row.is_24x7,
    publishedAt: row.published_at ?? null,
    recordVersion: row.record_version,
  });
}

export const SlaPolicyRowSchema = z.object({
  id: z.string().uuid(),
  code: z.string(),
  name: z.string(),
  status: z.enum(["active", "inactive"]),
  recordVersion: z.number().int().positive(),
});
export type SlaPolicyRow = z.infer<typeof SlaPolicyRowSchema>;

export function parseSlaPolicyRow(row: Record<string, unknown>): SlaPolicyRow {
  return SlaPolicyRowSchema.parse({
    id: row.id,
    code: row.code,
    name: row.name,
    status: row.status,
    recordVersion: row.record_version,
  });
}

export const SlaPolicyVersionRowSchema = z.object({
  id: z.string().uuid(),
  versionNumber: z.number().int().positive(),
  status: z.enum(["draft", "published", "superseded"]),
  channel: TicketChannelSchema,
  categoryId: z.string().uuid().nullable(),
  priority: TicketPrioritySchema.nullable(),
  customerAccountId: z.string().uuid().nullable(),
  queueId: z.string().uuid().nullable(),
  supportQueueId: z.string().uuid().nullable(),
  calendarId: z.string().uuid(),
  responseTargetMinutes: z.number().int().positive(),
  resolutionTargetMinutes: z.number().int().positive(),
  precedenceRank: z.number().int(),
  publishedAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
});
export type SlaPolicyVersionRow = z.infer<typeof SlaPolicyVersionRowSchema>;

export function parseSlaPolicyVersionRow(row: Record<string, unknown>): SlaPolicyVersionRow {
  return SlaPolicyVersionRowSchema.parse({
    id: row.id,
    versionNumber: row.version_number,
    status: row.status,
    channel: row.channel,
    categoryId: row.category_id ?? null,
    priority: row.priority ?? null,
    customerAccountId: row.customer_account_id ?? null,
    queueId: row.queue_id ?? null,
    supportQueueId: row.support_queue_id ?? null,
    calendarId: row.calendar_id,
    responseTargetMinutes: row.response_target_minutes,
    resolutionTargetMinutes: row.resolution_target_minutes,
    precedenceRank: row.precedence_rank,
    publishedAt: row.published_at ?? null,
    recordVersion: row.record_version,
  });
}

export const TicketSlaClockRowSchema = z.object({
  id: z.string().uuid(),
  ticketId: z.string().uuid(),
  slaPolicyVersionId: z.string().uuid(),
  slaCalendarVersionId: z.string().uuid(),
  status: SlaClockStatusSchema,
  startedAt: z.string(),
  responseTargetMinutes: z.number().int().positive(),
  responseStatus: SlaPhaseStatusSchema,
  responseMetAt: z.string().nullable(),
  responseBreachedAt: z.string().nullable(),
  resolutionTargetMinutes: z.number().int().positive(),
  resolutionStatus: SlaPhaseStatusSchema,
  resolutionMetAt: z.string().nullable(),
  resolutionBreachedAt: z.string().nullable(),
  lastEvaluatedAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
});
export type TicketSlaClockRow = z.infer<typeof TicketSlaClockRowSchema>;

export function parseTicketSlaClockRow(row: Record<string, unknown>): TicketSlaClockRow {
  return TicketSlaClockRowSchema.parse({
    id: row.id,
    ticketId: row.ticket_id,
    slaPolicyVersionId: row.sla_policy_version_id,
    slaCalendarVersionId: row.sla_calendar_version_id,
    status: row.status,
    startedAt: row.started_at,
    responseTargetMinutes: row.response_target_minutes,
    responseStatus: row.response_status,
    responseMetAt: row.response_met_at ?? null,
    responseBreachedAt: row.response_breached_at ?? null,
    resolutionTargetMinutes: row.resolution_target_minutes,
    resolutionStatus: row.resolution_status,
    resolutionMetAt: row.resolution_met_at ?? null,
    resolutionBreachedAt: row.resolution_breached_at ?? null,
    lastEvaluatedAt: row.last_evaluated_at ?? null,
    recordVersion: row.record_version,
  });
}

// Customer/requester-safe projection -- deliberately NO calendar/policy
// identity, no timestamps beyond status (mirrors app.get_ticket_sla_status_
// for_requester's own deliberately narrow column list, security impact
// section 16 "customer users see only customer-safe target/status").
export const TicketSlaStatusForRequesterRowSchema = z.object({
  ticketId: z.string().uuid(),
  responseTargetMinutes: z.number().int().positive(),
  responseStatus: SlaPhaseStatusSchema,
  resolutionTargetMinutes: z.number().int().positive(),
  resolutionStatus: SlaPhaseStatusSchema,
});
export type TicketSlaStatusForRequesterRow = z.infer<typeof TicketSlaStatusForRequesterRowSchema>;

export function parseTicketSlaStatusForRequesterRow(row: Record<string, unknown>): TicketSlaStatusForRequesterRow {
  return TicketSlaStatusForRequesterRowSchema.parse({
    ticketId: row.ticket_id,
    responseTargetMinutes: row.response_target_minutes,
    responseStatus: row.response_status,
    resolutionTargetMinutes: row.resolution_target_minutes,
    resolutionStatus: row.resolution_status,
  });
}

export const TicketSlaClockEventRowSchema = z.object({
  id: z.string().uuid(),
  phase: z.enum(["response", "resolution"]).nullable(),
  eventType: z.enum(["started", "paused", "resumed", "met", "breached", "reminder", "recalculated", "cancelled"]),
  reminderThresholdPct: z.number().int().nullable(),
  businessMinutesElapsed: z.number().int().nullable(),
  occurredAt: z.string(),
  actorLabel: z.string().nullable(),
  reason: z.string().nullable(),
});
export type TicketSlaClockEventRow = z.infer<typeof TicketSlaClockEventRowSchema>;

export function parseTicketSlaClockEventRow(row: Record<string, unknown>): TicketSlaClockEventRow {
  return TicketSlaClockEventRowSchema.parse({
    id: row.id,
    phase: row.phase ?? null,
    eventType: row.event_type,
    reminderThresholdPct: row.reminder_threshold_pct ?? null,
    businessMinutesElapsed: row.business_minutes_elapsed ?? null,
    occurredAt: row.occurred_at,
    actorLabel: row.actor_label ?? null,
    reason: row.reason ?? null,
  });
}

// --- SLA mutation inputs ---

export const CreateSlaCalendarInputSchema = z.object({
  tenantId: z.string().uuid(),
  code: z.string().min(1),
  name: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateSlaCalendarInput = z.infer<typeof CreateSlaCalendarInputSchema>;

export const CreateSlaCalendarVersionInputSchema = z.object({
  calendarId: z.string().uuid(),
  timezone: z.string().min(1),
  is24x7: z.boolean(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateSlaCalendarVersionInput = z.infer<typeof CreateSlaCalendarVersionInputSchema>;

export const AddSlaCalendarBusinessHoursInputSchema = z.object({
  calendarVersionId: z.string().uuid(),
  dayOfWeek: z.number().int().min(0).max(6),
  startTime: z.string(),
  endTime: z.string(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type AddSlaCalendarBusinessHoursInput = z.infer<typeof AddSlaCalendarBusinessHoursInputSchema>;

export const AddSlaCalendarHolidayInputSchema = z.object({
  calendarVersionId: z.string().uuid(),
  holidayDate: z.string(),
  name: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type AddSlaCalendarHolidayInput = z.infer<typeof AddSlaCalendarHolidayInputSchema>;

export const PublishSlaCalendarVersionInputSchema = z.object({
  versionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type PublishSlaCalendarVersionInput = z.infer<typeof PublishSlaCalendarVersionInputSchema>;

export const CreateSlaPolicyInputSchema = z.object({
  tenantId: z.string().uuid(),
  code: z.string().min(1),
  name: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateSlaPolicyInput = z.infer<typeof CreateSlaPolicyInputSchema>;

export const CreateSlaPolicyVersionInputSchema = z.object({
  policyId: z.string().uuid(),
  channel: TicketChannelSchema,
  categoryId: z.string().uuid().nullable(),
  priority: TicketPrioritySchema.nullable(),
  customerAccountId: z.string().uuid().nullable(),
  queueId: z.string().uuid().nullable(),
  supportQueueId: z.string().uuid().nullable(),
  calendarId: z.string().uuid(),
  responseTargetMinutes: z.number().int().positive(),
  resolutionTargetMinutes: z.number().int().positive(),
  precedenceRank: z.number().int(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateSlaPolicyVersionInput = z.infer<typeof CreateSlaPolicyVersionInputSchema>;

export const PublishSlaPolicyVersionInputSchema = z.object({
  versionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type PublishSlaPolicyVersionInput = z.infer<typeof PublishSlaPolicyVersionInputSchema>;

export const StartTicketSlaClockInputSchema = z.object({
  ticketId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type StartTicketSlaClockInput = z.infer<typeof StartTicketSlaClockInputSchema>;

export const PauseTicketSlaClockInputSchema = z.object({
  ticketId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  pauseReasonCode: SlaPauseReasonCodeSchema,
  reason: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type PauseTicketSlaClockInput = z.infer<typeof PauseTicketSlaClockInputSchema>;

export const ResumeTicketSlaClockInputSchema = z.object({
  ticketId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ResumeTicketSlaClockInput = z.infer<typeof ResumeTicketSlaClockInputSchema>;

export const RecalculateTicketSlaClockInputSchema = z.object({
  ticketId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RecalculateTicketSlaClockInput = z.infer<typeof RecalculateTicketSlaClockInputSchema>;

export const RunTicketSlaEvaluationBatchInputSchema = z.object({
  tenantId: z.string().uuid(),
  asOf: z.string().nullable(),
  periodLabel: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RunTicketSlaEvaluationBatchInput = z.infer<typeof RunTicketSlaEvaluationBatchInputSchema>;

// ===========================================================================
// HRT-290 (CG-S12-HRT-018): Ticket Assignment. Mirrors
// supabase/migrations/20260731140000_create_ticket_assignment.sql. Extends
// this module rather than a sibling one -- same "one canonical ticket
// service" reasoning HRT-289's own header already established for SLA.
// Routing rules/claim/accept/decline/auto-route are bounded to
// internal/customer channels (the migration's own decision 2) -- there is
// no helpdesk variant of any type below, matching app.assign_helpdesk_
// ticket/app.transfer_helpdesk_support_queue remaining entirely unmodified.
// ===========================================================================

export const TICKET_ROUTING_RULE_VERSION_STATUSES = ["draft", "published", "superseded", "archived"] as const;
export const TicketRoutingRuleVersionStatusSchema = z.enum(TICKET_ROUTING_RULE_VERSION_STATUSES);
export type TicketRoutingRuleVersionStatus = z.infer<typeof TicketRoutingRuleVersionStatusSchema>;

export const TICKET_ROUTING_ASSIGNMENT_MODES = ["manual", "least_loaded"] as const;
export const TicketRoutingAssignmentModeSchema = z.enum(TICKET_ROUTING_ASSIGNMENT_MODES);
export type TicketRoutingAssignmentMode = z.infer<typeof TicketRoutingAssignmentModeSchema>;

export const TICKET_ASSIGNMENT_EVENT_TYPES = [
  "auto_route",
  "manual_assign",
  "claim",
  "accept",
  "decline",
  "reassign",
  "unassign",
  "transfer",
] as const;
export const TicketAssignmentEventTypeSchema = z.enum(TICKET_ASSIGNMENT_EVENT_TYPES);
export type TicketAssignmentEventType = z.infer<typeof TicketAssignmentEventTypeSchema>;

export const TICKET_ASSIGNMENT_EVENT_SOURCES = ["rule_engine", "manual", "claim", "self"] as const;
export const TicketAssignmentEventSourceSchema = z.enum(TICKET_ASSIGNMENT_EVENT_SOURCES);
export type TicketAssignmentEventSource = z.infer<typeof TicketAssignmentEventSourceSchema>;

export const TicketRoutingRuleRowSchema = z.object({
  id: z.string().uuid(),
  code: z.string(),
  name: z.string(),
  status: z.enum(["active", "inactive"]),
  recordVersion: z.number().int().positive(),
});
export type TicketRoutingRuleRow = z.infer<typeof TicketRoutingRuleRowSchema>;

export function parseTicketRoutingRuleRow(row: Record<string, unknown>): TicketRoutingRuleRow {
  return TicketRoutingRuleRowSchema.parse({
    id: row.id,
    code: row.code,
    name: row.name,
    status: row.status,
    recordVersion: row.record_version,
  });
}

export const TicketRoutingRuleVersionRowSchema = z.object({
  id: z.string().uuid(),
  versionNumber: z.number().int().positive(),
  status: TicketRoutingRuleVersionStatusSchema,
  channel: TicketChannelSchema,
  categoryId: z.string().uuid().nullable(),
  priority: TicketPrioritySchema.nullable(),
  targetQueueId: z.string().uuid(),
  assignmentMode: TicketRoutingAssignmentModeSchema,
  maxActiveAssignmentsPerMember: z.number().int().positive().nullable(),
  precedenceRank: z.number().int(),
  publishedAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
});
export type TicketRoutingRuleVersionRow = z.infer<typeof TicketRoutingRuleVersionRowSchema>;

export function parseTicketRoutingRuleVersionRow(row: Record<string, unknown>): TicketRoutingRuleVersionRow {
  return TicketRoutingRuleVersionRowSchema.parse({
    id: row.id,
    versionNumber: row.version_number,
    status: row.status,
    channel: row.channel,
    categoryId: row.category_id ?? null,
    priority: row.priority ?? null,
    targetQueueId: row.target_queue_id,
    assignmentMode: row.assignment_mode,
    maxActiveAssignmentsPerMember: row.max_active_assignments_per_member ?? null,
    precedenceRank: row.precedence_rank,
    publishedAt: row.published_at ?? null,
    recordVersion: row.record_version,
  });
}

export const TicketRoutingPreviewRowSchema = z.object({
  matched: z.boolean(),
  ruleId: z.string().uuid().nullable(),
  ruleVersionId: z.string().uuid().nullable(),
  versionNumber: z.number().int().positive().nullable(),
  targetQueueId: z.string().uuid().nullable(),
  targetQueueCode: z.string().nullable(),
  assignmentMode: TicketRoutingAssignmentModeSchema.nullable(),
  maxActiveAssignmentsPerMember: z.number().int().positive().nullable(),
});
export type TicketRoutingPreviewRow = z.infer<typeof TicketRoutingPreviewRowSchema>;

export function parseTicketRoutingPreviewRow(row: Record<string, unknown>): TicketRoutingPreviewRow {
  return TicketRoutingPreviewRowSchema.parse({
    matched: row.matched,
    ruleId: row.rule_id ?? null,
    ruleVersionId: row.rule_version_id ?? null,
    versionNumber: row.version_number ?? null,
    targetQueueId: row.target_queue_id ?? null,
    targetQueueCode: row.target_queue_code ?? null,
    assignmentMode: row.assignment_mode ?? null,
    maxActiveAssignmentsPerMember: row.max_active_assignments_per_member ?? null,
  });
}

// Powers the assignment drawer's own "explainable eligibility" (section 15)
// -- every active queue member with a live eligibility bit/reason and a live
// workload count, never a raw employee directory.
export const TicketAssignmentCandidateRowSchema = z.object({
  employeeId: z.string().uuid(),
  employeeName: z.string(),
  isEligible: z.boolean(),
  activeTicketCount: z.number().int().nonnegative(),
  ineligibleReason: z.string().nullable(),
});
export type TicketAssignmentCandidateRow = z.infer<typeof TicketAssignmentCandidateRowSchema>;

export function parseTicketAssignmentCandidateRow(row: Record<string, unknown>): TicketAssignmentCandidateRow {
  return TicketAssignmentCandidateRowSchema.parse({
    employeeId: row.employee_id,
    employeeName: row.employee_name,
    isEligible: row.is_eligible,
    activeTicketCount: row.active_ticket_count,
    ineligibleReason: row.ineligible_reason ?? null,
  });
}

// Read-only workload aggregation (decision 1 -- never a second source of
// truth for who is assigned; a live COUNT(*) every call).
export const TicketQueueWorkloadRowSchema = z.object({
  employeeId: z.string().uuid(),
  employeeName: z.string(),
  activeTicketCount: z.number().int().nonnegative(),
  isEligible: z.boolean(),
});
export type TicketQueueWorkloadRow = z.infer<typeof TicketQueueWorkloadRowSchema>;

export function parseTicketQueueWorkloadRow(row: Record<string, unknown>): TicketQueueWorkloadRow {
  return TicketQueueWorkloadRowSchema.parse({
    employeeId: row.employee_id,
    employeeName: row.employee_name,
    activeTicketCount: row.active_ticket_count,
    isEligible: row.is_eligible,
  });
}

export const TicketAssignmentEventRowSchema = z.object({
  id: z.string().uuid(),
  eventType: TicketAssignmentEventTypeSchema,
  source: TicketAssignmentEventSourceSchema,
  ruleVersionId: z.string().uuid().nullable(),
  fromAssigneeEmployeeId: z.string().uuid().nullable(),
  fromAssigneeName: z.string().nullable(),
  toAssigneeEmployeeId: z.string().uuid().nullable(),
  toAssigneeName: z.string().nullable(),
  fromQueueId: z.string().uuid().nullable(),
  toQueueId: z.string().uuid().nullable(),
  reason: z.string().nullable(),
  actorLabel: z.string().nullable(),
  occurredAt: z.string(),
});
export type TicketAssignmentEventRow = z.infer<typeof TicketAssignmentEventRowSchema>;

export function parseTicketAssignmentEventRow(row: Record<string, unknown>): TicketAssignmentEventRow {
  return TicketAssignmentEventRowSchema.parse({
    id: row.id,
    eventType: row.event_type,
    source: row.source,
    ruleVersionId: row.rule_version_id ?? null,
    fromAssigneeEmployeeId: row.from_assignee_employee_id ?? null,
    fromAssigneeName: row.from_assignee_name ?? null,
    toAssigneeEmployeeId: row.to_assignee_employee_id ?? null,
    toAssigneeName: row.to_assignee_name ?? null,
    fromQueueId: row.from_queue_id ?? null,
    toQueueId: row.to_queue_id ?? null,
    reason: row.reason ?? null,
    actorLabel: row.actor_label ?? null,
    occurredAt: row.occurred_at,
  });
}

// --- Mutation inputs ---

export const CreateTicketRoutingRuleInputSchema = z.object({
  tenantId: z.string().uuid(),
  code: z.string().min(1),
  name: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateTicketRoutingRuleInput = z.infer<typeof CreateTicketRoutingRuleInputSchema>;

export const CreateTicketRoutingRuleVersionInputSchema = z.object({
  ruleId: z.string().uuid(),
  channel: TicketChannelSchema,
  categoryId: z.string().uuid().nullable(),
  priority: TicketPrioritySchema.nullable(),
  targetQueueId: z.string().uuid(),
  assignmentMode: TicketRoutingAssignmentModeSchema,
  maxActiveAssignmentsPerMember: z.number().int().positive().nullable(),
  precedenceRank: z.number().int(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateTicketRoutingRuleVersionInput = z.infer<typeof CreateTicketRoutingRuleVersionInputSchema>;

export const PublishTicketRoutingRuleVersionInputSchema = z.object({
  versionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type PublishTicketRoutingRuleVersionInput = z.infer<typeof PublishTicketRoutingRuleVersionInputSchema>;

export const ClaimTicketInputSchema = z.object({
  ticketId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ClaimTicketInput = z.infer<typeof ClaimTicketInputSchema>;

export const AcceptTicketAssignmentInputSchema = z.object({
  ticketId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type AcceptTicketAssignmentInput = z.infer<typeof AcceptTicketAssignmentInputSchema>;

export const DeclineTicketAssignmentInputSchema = z.object({
  ticketId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type DeclineTicketAssignmentInput = z.infer<typeof DeclineTicketAssignmentInputSchema>;

export const AutoRouteTicketInputSchema = z.object({
  ticketId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type AutoRouteTicketInput = z.infer<typeof AutoRouteTicketInputSchema>;

// ===========================================================================
// HRT-291 (CG-S12-HRT-019): Ticket Escalation. Mirrors
// supabase/migrations/20260731160000_create_ticket_escalation.sql. Bounded
// to internal/customer channels (the migration's own decision 1) -- there is
// no helpdesk variant of any type below, matching HRT-288/290's own
// precedent. Target is queue or employee only (decision 2) -- no role/team
// target type exists.
// ===========================================================================

export const TICKET_ESCALATION_TRIGGER_TYPES = [
  "sla_response_warning",
  "sla_response_breach",
  "sla_resolution_warning",
  "sla_resolution_breach",
  "priority_threshold",
  "inactivity",
  "assignment_failure",
] as const;
export const TicketEscalationTriggerTypeSchema = z.enum(TICKET_ESCALATION_TRIGGER_TYPES);
export type TicketEscalationTriggerType = z.infer<typeof TicketEscalationTriggerTypeSchema>;

// The ledger's own trigger_type also admits 'manual' (a manual escalation
// carries no configured level) -- a superset of the level-authoring enum
// above, never the other way around.
export const TICKET_ESCALATION_EVENT_TRIGGER_TYPES = [...TICKET_ESCALATION_TRIGGER_TYPES, "manual"] as const;
export const TicketEscalationEventTriggerTypeSchema = z.enum(TICKET_ESCALATION_EVENT_TRIGGER_TYPES);
export type TicketEscalationEventTriggerType = z.infer<typeof TicketEscalationEventTriggerTypeSchema>;

export const TICKET_ESCALATION_TARGET_TYPES = ["queue", "employee"] as const;
export const TicketEscalationTargetTypeSchema = z.enum(TICKET_ESCALATION_TARGET_TYPES);
export type TicketEscalationTargetType = z.infer<typeof TicketEscalationTargetTypeSchema>;

export const TICKET_ESCALATION_STATUSES = ["active", "acknowledged", "resolved"] as const;
export const TicketEscalationStatusSchema = z.enum(TICKET_ESCALATION_STATUSES);
export type TicketEscalationStatus = z.infer<typeof TicketEscalationStatusSchema>;

export const TICKET_ESCALATION_EVENT_TYPES = [
  "triggered",
  "notified",
  "notification_failed",
  "reassigned",
  "reassign_skipped",
  "acknowledged",
  "suppressed",
  "suppression_ended",
  "resolved",
  "recovered",
] as const;
export const TicketEscalationEventTypeSchema = z.enum(TICKET_ESCALATION_EVENT_TYPES);
export type TicketEscalationEventType = z.infer<typeof TicketEscalationEventTypeSchema>;

export const TicketEscalationPolicyRowSchema = z.object({
  id: z.string().uuid(),
  code: z.string(),
  name: z.string(),
  status: z.enum(["active", "inactive"]),
  recordVersion: z.number().int().positive(),
});
export type TicketEscalationPolicyRow = z.infer<typeof TicketEscalationPolicyRowSchema>;

export function parseTicketEscalationPolicyRow(row: Record<string, unknown>): TicketEscalationPolicyRow {
  return TicketEscalationPolicyRowSchema.parse({
    id: row.id,
    code: row.code,
    name: row.name,
    status: row.status,
    recordVersion: row.record_version,
  });
}

export const TicketEscalationPolicyVersionRowSchema = z.object({
  id: z.string().uuid(),
  versionNumber: z.number().int().positive(),
  status: z.enum(["draft", "published", "superseded"]),
  channel: TicketChannelSchema,
  categoryId: z.string().uuid().nullable(),
  priority: TicketPrioritySchema.nullable(),
  queueId: z.string().uuid().nullable(),
  precedenceRank: z.number().int(),
  publishedAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
});
export type TicketEscalationPolicyVersionRow = z.infer<typeof TicketEscalationPolicyVersionRowSchema>;

export function parseTicketEscalationPolicyVersionRow(row: Record<string, unknown>): TicketEscalationPolicyVersionRow {
  return TicketEscalationPolicyVersionRowSchema.parse({
    id: row.id,
    versionNumber: row.version_number,
    status: row.status,
    channel: row.channel,
    categoryId: row.category_id ?? null,
    priority: row.priority ?? null,
    queueId: row.queue_id ?? null,
    precedenceRank: row.precedence_rank,
    publishedAt: row.published_at ?? null,
    recordVersion: row.record_version,
  });
}

export const TicketEscalationLevelRowSchema = z.object({
  id: z.string().uuid(),
  levelNumber: z.number().int().positive(),
  triggerType: TicketEscalationTriggerTypeSchema,
  thresholdMinutes: z.number().int().positive().nullable(),
  minPriority: TicketPrioritySchema.nullable(),
  targetType: TicketEscalationTargetTypeSchema,
  targetQueueId: z.string().uuid().nullable(),
  targetQueueCode: z.string().nullable(),
  targetEmployeeId: z.string().uuid().nullable(),
  targetEmployeeName: z.string().nullable(),
  actionNotify: z.boolean(),
  actionReassign: z.boolean(),
  cooldownMinutes: z.number().int().positive(),
});
export type TicketEscalationLevelRow = z.infer<typeof TicketEscalationLevelRowSchema>;

export function parseTicketEscalationLevelRow(row: Record<string, unknown>): TicketEscalationLevelRow {
  return TicketEscalationLevelRowSchema.parse({
    id: row.id,
    levelNumber: row.level_number,
    triggerType: row.trigger_type,
    thresholdMinutes: row.threshold_minutes ?? null,
    minPriority: row.min_priority ?? null,
    targetType: row.target_type,
    targetQueueId: row.target_queue_id ?? null,
    targetQueueCode: row.target_queue_code ?? null,
    targetEmployeeId: row.target_employee_id ?? null,
    targetEmployeeName: row.target_employee_name ?? null,
    actionNotify: row.action_notify,
    actionReassign: row.action_reassign,
    cooldownMinutes: row.cooldown_minutes,
  });
}

export const TicketEscalationPreviewRowSchema = z.object({
  matched: z.boolean(),
  policyId: z.string().uuid().nullable(),
  policyVersionId: z.string().uuid().nullable(),
  versionNumber: z.number().int().positive().nullable(),
  levelCount: z.number().int().nonnegative().nullable(),
});
export type TicketEscalationPreviewRow = z.infer<typeof TicketEscalationPreviewRowSchema>;

export function parseTicketEscalationPreviewRow(row: Record<string, unknown>): TicketEscalationPreviewRow {
  return TicketEscalationPreviewRowSchema.parse({
    matched: row.matched,
    policyId: row.policy_id ?? null,
    policyVersionId: row.policy_version_id ?? null,
    versionNumber: row.version_number ?? null,
    levelCount: row.level_count ?? null,
  });
}

// Staff-only full projection -- never returned to a requester (decision 12).
export const TicketEscalationRowSchema = z.object({
  id: z.string().uuid(),
  policyVersionId: z.string().uuid().nullable(),
  status: TicketEscalationStatusSchema,
  currentLevel: z.number().int().positive(),
  currentLevelId: z.string().uuid().nullable(),
  lastTriggerType: TicketEscalationEventTriggerTypeSchema,
  acknowledgedAt: z.string().nullable(),
  acknowledgedBy: z.string().nullable(),
  resolvedAt: z.string().nullable(),
  resolvedReason: z.enum(["ticket_resolved", "ticket_closed", "ticket_cancelled", "manual_recovery"]).nullable(),
  lastTriggeredAt: z.string(),
  recordVersion: z.number().int().positive(),
});
export type TicketEscalationRow = z.infer<typeof TicketEscalationRowSchema>;

export function parseTicketEscalationRow(row: Record<string, unknown>): TicketEscalationRow {
  return TicketEscalationRowSchema.parse({
    id: row.id,
    policyVersionId: row.policy_version_id ?? null,
    status: row.status,
    currentLevel: row.current_level,
    currentLevelId: row.current_level_id ?? null,
    lastTriggerType: row.last_trigger_type,
    acknowledgedAt: row.acknowledged_at ?? null,
    acknowledgedBy: row.acknowledged_by ?? null,
    resolvedAt: row.resolved_at ?? null,
    resolvedReason: row.resolved_reason ?? null,
    lastTriggeredAt: row.last_triggered_at,
    recordVersion: row.record_version,
  });
}

// Customer/requester-safe projection -- a SINGLE boolean, structurally
// incapable of carrying level/target/trigger/hierarchy (decision 12,
// security impact section 16). Mirrors TicketSlaStatusForRequesterRowSchema's
// own deliberately narrow shape.
export const TicketEscalationStatusForRequesterRowSchema = z.object({
  isEscalated: z.boolean(),
});
export type TicketEscalationStatusForRequesterRow = z.infer<typeof TicketEscalationStatusForRequesterRowSchema>;

export function parseTicketEscalationStatusForRequesterRow(row: Record<string, unknown>): TicketEscalationStatusForRequesterRow {
  return TicketEscalationStatusForRequesterRowSchema.parse({
    isEscalated: row.is_escalated,
  });
}

export const TicketEscalationEventRowSchema = z.object({
  id: z.string().uuid(),
  levelNumber: z.number().int().nonnegative(),
  triggerType: TicketEscalationEventTriggerTypeSchema,
  eventType: TicketEscalationEventTypeSchema,
  targetType: TicketEscalationTargetTypeSchema.nullable(),
  targetQueueId: z.string().uuid().nullable(),
  targetQueueCode: z.string().nullable(),
  targetEmployeeId: z.string().uuid().nullable(),
  targetEmployeeName: z.string().nullable(),
  reason: z.string().nullable(),
  actorLabel: z.string().nullable(),
  occurredAt: z.string(),
});
export type TicketEscalationEventRow = z.infer<typeof TicketEscalationEventRowSchema>;

export function parseTicketEscalationEventRow(row: Record<string, unknown>): TicketEscalationEventRow {
  return TicketEscalationEventRowSchema.parse({
    id: row.id,
    levelNumber: row.level_number,
    triggerType: row.trigger_type,
    eventType: row.event_type,
    targetType: row.target_type ?? null,
    targetQueueId: row.target_queue_id ?? null,
    targetQueueCode: row.target_queue_code ?? null,
    targetEmployeeId: row.target_employee_id ?? null,
    targetEmployeeName: row.target_employee_name ?? null,
    reason: row.reason ?? null,
    actorLabel: row.actor_label ?? null,
    occurredAt: row.occurred_at,
  });
}

export const TicketEscalationSuppressionRowSchema = z.object({
  id: z.string().uuid(),
  reason: z.string(),
  expiresAt: z.string(),
  suppressedBy: z.string().nullable(),
  revokedAt: z.string().nullable(),
  revokedBy: z.string().nullable(),
  revokedReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
});
export type TicketEscalationSuppressionRow = z.infer<typeof TicketEscalationSuppressionRowSchema>;

export function parseTicketEscalationSuppressionRow(row: Record<string, unknown>): TicketEscalationSuppressionRow {
  return TicketEscalationSuppressionRowSchema.parse({
    id: row.id,
    reason: row.reason,
    expiresAt: row.expires_at,
    suppressedBy: row.suppressed_by ?? null,
    revokedAt: row.revoked_at ?? null,
    revokedBy: row.revoked_by ?? null,
    revokedReason: row.revoked_reason ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
  });
}

// The breach/stuck queue browser (decision 13) -- a dedicated, minimal read
// row, never a widened TicketListRow/MyTicketListRow.
export const TicketBreachQueueRowSchema = z.object({
  ticketId: z.string().uuid(),
  ticketNumber: z.string(),
  subject: z.string(),
  status: TicketStatusSchema,
  priority: TicketPrioritySchema,
  queueCode: z.string(),
  currentLevel: z.number().int().positive(),
  lastTriggerType: TicketEscalationEventTriggerTypeSchema,
  escalationStatus: TicketEscalationStatusSchema,
  lastTriggeredAt: z.string(),
  acknowledgedAt: z.string().nullable(),
});
export type TicketBreachQueueRow = z.infer<typeof TicketBreachQueueRowSchema>;

export function parseTicketBreachQueueRow(row: Record<string, unknown>): TicketBreachQueueRow {
  return TicketBreachQueueRowSchema.parse({
    ticketId: row.ticket_id,
    ticketNumber: row.ticket_number,
    subject: row.subject,
    status: row.status,
    priority: row.priority,
    queueCode: row.queue_code,
    currentLevel: row.current_level,
    lastTriggerType: row.last_trigger_type,
    escalationStatus: row.escalation_status,
    lastTriggeredAt: row.last_triggered_at,
    acknowledgedAt: row.acknowledged_at ?? null,
  });
}

// --- Mutation inputs ---

export const CreateTicketEscalationPolicyInputSchema = z.object({
  tenantId: z.string().uuid(),
  code: z.string().min(1),
  name: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateTicketEscalationPolicyInput = z.infer<typeof CreateTicketEscalationPolicyInputSchema>;

export const CreateTicketEscalationPolicyVersionInputSchema = z.object({
  policyId: z.string().uuid(),
  channel: TicketChannelSchema,
  categoryId: z.string().uuid().nullable(),
  priority: TicketPrioritySchema.nullable(),
  queueId: z.string().uuid().nullable(),
  precedenceRank: z.number().int(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateTicketEscalationPolicyVersionInput = z.infer<typeof CreateTicketEscalationPolicyVersionInputSchema>;

export const AddTicketEscalationLevelInputSchema = z.object({
  policyVersionId: z.string().uuid(),
  levelNumber: z.number().int().positive(),
  triggerType: TicketEscalationTriggerTypeSchema,
  thresholdMinutes: z.number().int().positive().nullable(),
  minPriority: TicketPrioritySchema.nullable(),
  targetType: TicketEscalationTargetTypeSchema,
  targetQueueId: z.string().uuid().nullable(),
  targetEmployeeId: z.string().uuid().nullable(),
  actionNotify: z.boolean(),
  actionReassign: z.boolean(),
  cooldownMinutes: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type AddTicketEscalationLevelInput = z.infer<typeof AddTicketEscalationLevelInputSchema>;

export const PublishTicketEscalationPolicyVersionInputSchema = z.object({
  versionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type PublishTicketEscalationPolicyVersionInput = z.infer<typeof PublishTicketEscalationPolicyVersionInputSchema>;

export const EscalateTicketInputSchema = z.object({
  ticketId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  targetType: TicketEscalationTargetTypeSchema,
  targetQueueId: z.string().uuid().nullable(),
  targetEmployeeId: z.string().uuid().nullable(),
  reassign: z.boolean(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type EscalateTicketInput = z.infer<typeof EscalateTicketInputSchema>;

export const AcknowledgeTicketEscalationInputSchema = z.object({
  ticketId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type AcknowledgeTicketEscalationInput = z.infer<typeof AcknowledgeTicketEscalationInputSchema>;

export const ResolveTicketEscalationInputSchema = z.object({
  ticketId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ResolveTicketEscalationInput = z.infer<typeof ResolveTicketEscalationInputSchema>;

export const SuppressTicketEscalationInputSchema = z.object({
  ticketId: z.string().uuid(),
  reason: z.string().min(1),
  expiresAt: z.string(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type SuppressTicketEscalationInput = z.infer<typeof SuppressTicketEscalationInputSchema>;

export const RevokeTicketEscalationSuppressionInputSchema = z.object({
  ticketId: z.string().uuid(),
  suppressionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RevokeTicketEscalationSuppressionInput = z.infer<typeof RevokeTicketEscalationSuppressionInputSchema>;

export const RunTicketEscalationEvaluationBatchInputSchema = z.object({
  tenantId: z.string().uuid(),
  asOf: z.string().nullable(),
  periodLabel: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RunTicketEscalationEvaluationBatchInput = z.infer<typeof RunTicketEscalationEvaluationBatchInputSchema>;

// ===========================================================================
// HRT-292 (CG-S12-HRT-020): Typed Ticket-Linked Records. Mirrors
// supabase/migrations/20260731170000_create_ticket_linked_records.sql
// exactly -- entity_type is the registry (decision 1), relationship is the
// small fixed enum, safe_snapshot is always the bounded {label, detail,
// status} shape (decision 2), never a per-type schema.
// ===========================================================================

export const TICKET_LINK_ENTITY_TYPES = ["shipment", "invoice", "warehouse", "vendor", "customer", "user"] as const;
export const TicketLinkEntityTypeSchema = z.enum(TICKET_LINK_ENTITY_TYPES);
export type TicketLinkEntityType = z.infer<typeof TicketLinkEntityTypeSchema>;

// The subset a customer_user-layer caller may search/link/see (decision 7)
// -- never vendor or user. Kept as a plain literal array (not derived from
// the full list at the type level) so a drift between this and the live
// app.ticket_link_customer_safe_entity_types() is a real, visible db-test
// failure rather than silently inherited.
export const TICKET_LINK_CUSTOMER_SAFE_ENTITY_TYPES = ["shipment", "invoice", "warehouse", "customer"] as const;

export const TICKET_LINK_RELATIONSHIPS = ["primary_subject", "related", "affected", "context"] as const;
export const TicketLinkRelationshipSchema = z.enum(TICKET_LINK_RELATIONSHIPS);
export type TicketLinkRelationship = z.infer<typeof TicketLinkRelationshipSchema>;

export const TICKET_LINK_STATUSES = ["active", "removed"] as const;
export const TicketLinkStatusSchema = z.enum(TICKET_LINK_STATUSES);
export type TicketLinkStatus = z.infer<typeof TicketLinkStatusSchema>;

export const TICKET_LINK_EVENT_TYPES = [
  "linked", "unlinked", "link_denied", "search_denied", "summary_accessed", "deep_link_accessed",
] as const;
export const TicketLinkEventTypeSchema = z.enum(TICKET_LINK_EVENT_TYPES);
export type TicketLinkEventType = z.infer<typeof TicketLinkEventTypeSchema>;

// A candidate row from app.search_ticket_link_candidates -- already
// independently authorized for the calling principal (never a row the
// caller cannot see, C-05).
export const TicketLinkCandidateRowSchema = z.object({
  entityId: z.string().uuid(),
  primaryLabel: z.string(),
  secondaryLabel: z.string().nullable(),
  statusLabel: z.string().nullable(),
});
export type TicketLinkCandidateRow = z.infer<typeof TicketLinkCandidateRowSchema>;

export function parseTicketLinkCandidateRow(row: Record<string, unknown>): TicketLinkCandidateRow {
  return TicketLinkCandidateRowSchema.parse({
    entityId: row.entity_id,
    primaryLabel: row.primary_label,
    secondaryLabel: row.secondary_label ?? null,
    statusLabel: row.status_label ?? null,
  });
}

// One row from app.list_ticket_links -- label/detail/statusLabel are a LIVE,
// principal-fresh re-check (decision 6), never the stored safe_snapshot;
// liveAvailable=false collapses "deleted" and "revoked" into one
// undifferentiated outward state deliberately (never leaks which).
export const TicketLinkRowSchema = z.object({
  id: z.string().uuid(),
  entityType: TicketLinkEntityTypeSchema,
  entityId: z.string().uuid(),
  relationship: TicketLinkRelationshipSchema,
  status: TicketLinkStatusSchema,
  liveAvailable: z.boolean(),
  label: z.string().nullable(),
  detail: z.string().nullable(),
  statusLabel: z.string(),
  linkedAt: z.string(),
  createdBy: z.string().nullable(),
  recordVersion: z.number().int().positive(),
});
export type TicketLinkRow = z.infer<typeof TicketLinkRowSchema>;

export function parseTicketLinkRow(row: Record<string, unknown>): TicketLinkRow {
  return TicketLinkRowSchema.parse({
    id: row.id,
    entityType: row.entity_type,
    entityId: row.entity_id,
    relationship: row.relationship,
    status: row.status,
    liveAvailable: row.live_available,
    label: row.label ?? null,
    detail: row.detail ?? null,
    statusLabel: row.status_label,
    linkedAt: row.linked_at,
    createdBy: row.created_by ?? null,
    recordVersion: row.record_version,
  });
}

export const TicketLinkEventRowSchema = z.object({
  id: z.string().uuid(),
  entityType: TicketLinkEntityTypeSchema.nullable(),
  entityId: z.string().uuid().nullable(),
  relationship: TicketLinkRelationshipSchema.nullable(),
  eventType: TicketLinkEventTypeSchema,
  reason: z.string().nullable(),
  actorAuthUserId: z.string().uuid().nullable(),
  actorLabel: z.string().nullable(),
  occurredAt: z.string(),
});
export type TicketLinkEventRow = z.infer<typeof TicketLinkEventRowSchema>;

export function parseTicketLinkEventRow(row: Record<string, unknown>): TicketLinkEventRow {
  return TicketLinkEventRowSchema.parse({
    id: row.id,
    entityType: row.entity_type ?? null,
    entityId: row.entity_id ?? null,
    relationship: row.relationship ?? null,
    eventType: row.event_type,
    reason: row.reason ?? null,
    actorAuthUserId: row.actor_auth_user_id ?? null,
    actorLabel: row.actor_label ?? null,
    occurredAt: row.occurred_at,
  });
}

export const SearchTicketLinkCandidatesInputSchema = z.object({
  ticketId: z.string().uuid(),
  entityType: TicketLinkEntityTypeSchema,
  searchText: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  limit: z.number().int().positive().nullable(),
});
export type SearchTicketLinkCandidatesInput = z.infer<typeof SearchTicketLinkCandidatesInputSchema>;

export const LinkTicketRecordInputSchema = z.object({
  ticketId: z.string().uuid(),
  entityType: TicketLinkEntityTypeSchema,
  entityId: z.string().uuid(),
  relationship: TicketLinkRelationshipSchema,
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type LinkTicketRecordInput = z.infer<typeof LinkTicketRecordInputSchema>;

export const UnlinkTicketRecordInputSchema = z.object({
  linkId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type UnlinkTicketRecordInput = z.infer<typeof UnlinkTicketRecordInputSchema>;

export const RecordTicketLinkAccessDenialInputSchema = z.object({
  tenantId: z.string().uuid(),
  ticketId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().nullable(),
  entityType: TicketLinkEntityTypeSchema,
  entityId: z.string().uuid().nullable(),
  reason: z.string().nullable(),
});
export type RecordTicketLinkAccessDenialInput = z.infer<typeof RecordTicketLinkAccessDenialInputSchema>;

export const TICKET_LINK_SUMMARY_ACCESS_TYPES = ["summary_viewed", "deep_link_opened"] as const;
export const TicketLinkSummaryAccessTypeSchema = z.enum(TICKET_LINK_SUMMARY_ACCESS_TYPES);
export type TicketLinkSummaryAccessType = z.infer<typeof TicketLinkSummaryAccessTypeSchema>;

export const RecordTicketLinkSummaryAccessInputSchema = z.object({
  linkId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().nullable(),
  accessType: TicketLinkSummaryAccessTypeSchema,
});
export type RecordTicketLinkSummaryAccessInput = z.infer<typeof RecordTicketLinkSummaryAccessInputSchema>;

// ===========================================================================
// CPL-313 (CG-S13-CPL-015, Prompt 313): Portal ticket-linked records --
// warehouse_order/document. A deliberately SEPARATE, PARALLEL type family
// from TICKET_LINK_ENTITY_TYPES above (never merged into it) -- widening
// the existing six-value TICKET_LINK_ENTITY_TYPES/TicketLinkEntityTypeSchema
// would break an existing, protected test assertion
// (server/contracts/ticketing/ticketing.test.ts, "TICKET_LINK_ENTITY_TYPES
// is exactly the six documented types") and the equivalent live db-test
// assertion in scripts/db-tests/ticketing-linked-records.sql -- both
// discovered BEFORE writing any code, per the source prompt's own
// instruction to check app._ticket_link_resolve_candidate's actual body
// first. Mirrors supabase/migrations/20260801140000_create_customer_portal_
// ticket_linked_records.sql exactly; see that migration's own header for
// full design rationale.
// ===========================================================================

export const TICKET_PORTAL_LINK_ENTITY_TYPES = ["warehouse_order", "document"] as const;
export const TicketPortalLinkEntityTypeSchema = z.enum(TICKET_PORTAL_LINK_ENTITY_TYPES);
export type TicketPortalLinkEntityType = z.infer<typeof TicketPortalLinkEntityTypeSchema>;

// A candidate row from app.search_ticket_portal_link_candidates /
// app.search_customer_ticket_portal_link_candidates_precreate -- already
// independently authorized for the calling principal (C-05).
export const TicketPortalLinkCandidateRowSchema = z.object({
  entityId: z.string().uuid(),
  primaryLabel: z.string(),
  secondaryLabel: z.string().nullable(),
  statusLabel: z.string().nullable(),
});
export type TicketPortalLinkCandidateRow = z.infer<typeof TicketPortalLinkCandidateRowSchema>;

export function parseTicketPortalLinkCandidateRow(row: Record<string, unknown>): TicketPortalLinkCandidateRow {
  return TicketPortalLinkCandidateRowSchema.parse({
    entityId: row.entity_id,
    primaryLabel: row.primary_label,
    secondaryLabel: row.secondary_label ?? null,
    statusLabel: row.status_label ?? null,
  });
}

// One row from app.list_ticket_portal_links -- label/detail/statusLabel are
// a LIVE, principal-fresh re-check, never the stored safe_snapshot;
// liveAvailable=false collapses "deleted" and "revoked" into one
// undifferentiated outward state deliberately (mirrors TicketLinkRow).
export const TicketPortalLinkRowSchema = z.object({
  id: z.string().uuid(),
  entityType: TicketPortalLinkEntityTypeSchema,
  entityId: z.string().uuid(),
  relationship: TicketLinkRelationshipSchema,
  status: TicketLinkStatusSchema,
  liveAvailable: z.boolean(),
  label: z.string().nullable(),
  detail: z.string().nullable(),
  statusLabel: z.string(),
  linkedAt: z.string(),
  createdBy: z.string().nullable(),
  recordVersion: z.number().int().positive(),
});
export type TicketPortalLinkRow = z.infer<typeof TicketPortalLinkRowSchema>;

export function parseTicketPortalLinkRow(row: Record<string, unknown>): TicketPortalLinkRow {
  return TicketPortalLinkRowSchema.parse({
    id: row.id,
    entityType: row.entity_type,
    entityId: row.entity_id,
    relationship: row.relationship,
    status: row.status,
    liveAvailable: row.live_available,
    label: row.label ?? null,
    detail: row.detail ?? null,
    statusLabel: row.status_label,
    linkedAt: row.linked_at,
    createdBy: row.created_by ?? null,
    recordVersion: row.record_version,
  });
}

export const LinkTicketPortalRecordInputSchema = z.object({
  ticketId: z.string().uuid(),
  entityType: TicketPortalLinkEntityTypeSchema,
  entityId: z.string().uuid(),
  relationship: TicketLinkRelationshipSchema,
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type LinkTicketPortalRecordInput = z.infer<typeof LinkTicketPortalRecordInputSchema>;

export const UnlinkTicketPortalRecordInputSchema = z.object({
  linkId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type UnlinkTicketPortalRecordInput = z.infer<typeof UnlinkTicketPortalRecordInputSchema>;

// The ticket CREATE form's own picker offers exactly these four types --
// deliberately spans both TICKET_LINK_ENTITY_TYPES (shipment/invoice) and
// TICKET_PORTAL_LINK_ENTITY_TYPES (warehouse_order/document) at once,
// mirroring app.search_customer_ticket_link_candidates_precreate's own
// identical span (see that function's own comment). Lives here, not in
// app/(tenant)/[tenantSlug]/customer-tickets/actions.ts, because that file
// is a "use server" module -- every export from a "use server" file must be
// an async function, so a plain runtime constant cannot live there (a real
// `next build` failure this checkpoint's own build caught live, not reasoned
// about in advance).
export const TICKET_PRECREATE_LINK_ENTITY_TYPES = ["shipment", "invoice", "warehouse_order", "document"] as const;
export const TicketPrecreateLinkEntityTypeSchema = z.enum(TICKET_PRECREATE_LINK_ENTITY_TYPES);
export type TicketPrecreateLinkEntityType = z.infer<typeof TicketPrecreateLinkEntityTypeSchema>;
