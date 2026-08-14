/**
 * Ticketing contract (HRT-286, CG-S12-HRT-014) -- the canonical, cross-channel
 * ticket/conversation model's TypeScript surface. Mirrors
 * supabase/migrations/20260731060000_create_ticketing_internal.sql's tables/
 * RPCs. Follows the exact directory convention every prior HRT checkpoint
 * established: Zod schemas here, list/read projections in
 * server/queries/ticketing.ts, RPC-calling mutation wrappers with an
 * enumerated error-code type in server/mutations/ticketing.ts.
 *
 * Directory/naming choice (disclosed, since Prompt 287/288 depend on it):
 * `server/contracts/ticketing/`, `server/queries/ticketing.ts`,
 * `server/mutations/ticketing.ts` -- "ticketing", not "internal-ticket", to
 * anticipate the SAME files growing a `channel` dimension across all three
 * future channels (customer, helpdesk) without a rename. Every row/input type
 * below is already channel-agnostic where the underlying RPC is (e.g.
 * `TicketRow`); channel is a plain field, never a type discriminant of its
 * own file/module.
 */

import { z } from "zod";

export const TICKET_CHANNELS = ["internal"] as const;
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
] as const;
export const TicketEventTypeSchema = z.enum(TICKET_EVENT_TYPES);
export type TicketEventType = z.infer<typeof TicketEventTypeSchema>;

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
  requesterEmployeeId: z.string().uuid(),
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
    requesterEmployeeId: row.requester_employee_id,
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
