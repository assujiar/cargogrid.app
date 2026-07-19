/**
 * Notification engine contract (PLT-127, CG-S6-PLT-024). Mirrors
 * supabase/migrations/20260719130000_create_notification_engine.sql's
 * app.notification_types/app.notification_preferences/app.notifications/
 * app.notification_delivery_attempts shape and the app.register_notification_type /
 * app.publish_notification_template / app.set_notification_preference /
 * app.queue_notification / app.record_notification_delivery_attempt /
 * app.mark_notification_read / app.list_notifications_for_recipient /
 * app.count_unread_notifications / app.get_notification_preferences /
 * app.render_notification_template RPCs.
 *
 * A notification *template* is not modeled here as its own row type -- it is PLT-121's
 * own ConfigVersion/config_items (config_type_code='notification:<code>'), reused
 * directly (this migration's own header). `publishNotificationTemplate` therefore still
 * returns a `ConfigVersion` (server/contracts/config/config.ts), not a bespoke type.
 */

import { z } from "zod";
import { ConfigVersionSchema, type ConfigVersion } from "../config/config.ts";

export const NOTIFICATION_CHANNELS = ["in_app", "email"] as const;
export const NotificationChannelSchema = z.enum(NOTIFICATION_CHANNELS);
export type NotificationChannel = z.infer<typeof NotificationChannelSchema>;

export const NOTIFICATION_STATUSES = ["queued", "sent", "failed", "skipped"] as const;
export const NotificationStatusSchema = z.enum(NOTIFICATION_STATUSES);
export type NotificationStatus = z.infer<typeof NotificationStatusSchema>;

export const DELIVERY_ATTEMPT_STATUSES = ["success", "failed"] as const;
export const DeliveryAttemptStatusSchema = z.enum(DELIVERY_ATTEMPT_STATUSES);
export type DeliveryAttemptStatus = z.infer<typeof DeliveryAttemptStatusSchema>;

export const NotificationTypeSchema = z.object({
  code: z.string(),
  name: z.string(),
  ownerPrimitiveCode: z.string(),
  registeredBy: z.string().nullable(),
  createdAt: z.string(),
});
export type NotificationType = z.infer<typeof NotificationTypeSchema>;

export const NotificationPreferenceSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  authUserId: z.string().uuid(),
  notificationTypeCode: z.string(),
  channel: NotificationChannelSchema,
  enabled: z.boolean(),
  updatedAt: z.string(),
});
export type NotificationPreference = z.infer<typeof NotificationPreferenceSchema>;

export const NotificationSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  configVersionId: z.string().uuid(),
  notificationTypeCode: z.string(),
  recipientAuthUserId: z.string().uuid(),
  requestedChannel: NotificationChannelSchema,
  effectiveChannel: NotificationChannelSchema,
  locale: z.string(),
  subject: z.string(),
  body: z.string(),
  context: z.record(z.string(), z.unknown()),
  status: NotificationStatusSchema,
  dedupeKey: z.string(),
  triggeredByAuthUserId: z.string().uuid().nullable(),
  triggeredBy: z.string().nullable(),
  readAt: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type Notification = z.infer<typeof NotificationSchema>;

export const NotificationDeliveryAttemptSchema = z.object({
  id: z.string().uuid(),
  notificationId: z.string().uuid(),
  attemptNumber: z.number().int().positive(),
  status: DeliveryAttemptStatusSchema,
  errorMessage: z.string().nullable(),
  attemptedAt: z.string(),
});
export type NotificationDeliveryAttempt = z.infer<typeof NotificationDeliveryAttemptSchema>;

export const RegisterNotificationTypeInputSchema = z.object({
  code: z.string().min(1),
  name: z.string().min(1),
  ownerPrimitiveCode: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  registeredBy: z.string().min(1),
});
export type RegisterNotificationTypeInput = z.input<typeof RegisterNotificationTypeInputSchema>;

export const PublishNotificationTemplateInputSchema = z.object({
  versionId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  effectiveFrom: z.string().nullable().default(null),
  actorLabel: z.string().min(1),
});
export type PublishNotificationTemplateInput = z.input<typeof PublishNotificationTemplateInputSchema>;

export const SetNotificationPreferenceInputSchema = z.object({
  tenantId: z.string().uuid(),
  authUserId: z.string().uuid(),
  notificationTypeCode: z.string().min(1),
  channel: NotificationChannelSchema,
  enabled: z.boolean(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SetNotificationPreferenceInput = z.input<typeof SetNotificationPreferenceInputSchema>;

export const GetNotificationPreferencesInputSchema = z.object({
  tenantId: z.string().uuid(),
  authUserId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type GetNotificationPreferencesInput = z.input<typeof GetNotificationPreferencesInputSchema>;

export const QueueNotificationInputSchema = z.object({
  configVersionId: z.string().uuid(),
  tenantId: z.string().uuid(),
  notificationTypeCode: z.string().min(1),
  recipientAuthUserId: z.string().uuid(),
  channel: NotificationChannelSchema,
  locale: z.string().min(1).default("en"),
  context: z.record(z.string(), z.unknown()).default({}),
  dedupeKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  triggeredBy: z.string().min(1),
});
export type QueueNotificationInput = z.input<typeof QueueNotificationInputSchema>;

export const RecordNotificationDeliveryAttemptInputSchema = z.object({
  notificationId: z.string().uuid(),
  status: DeliveryAttemptStatusSchema,
  errorMessage: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RecordNotificationDeliveryAttemptInput = z.input<typeof RecordNotificationDeliveryAttemptInputSchema>;

export const MarkNotificationReadInputSchema = z.object({
  notificationId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type MarkNotificationReadInput = z.input<typeof MarkNotificationReadInputSchema>;

export const ListNotificationsForRecipientInputSchema = z.object({
  tenantId: z.string().uuid(),
  recipientAuthUserId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  unreadOnly: z.boolean().default(false),
});
export type ListNotificationsForRecipientInput = z.input<typeof ListNotificationsForRecipientInputSchema>;

export const CountUnreadNotificationsInputSchema = z.object({
  tenantId: z.string().uuid(),
  recipientAuthUserId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type CountUnreadNotificationsInput = z.input<typeof CountUnreadNotificationsInputSchema>;

export const RenderNotificationTemplatePreviewInputSchema = z.object({
  configVersionId: z.string().uuid(),
  locale: z.string().min(1),
  context: z.record(z.string(), z.unknown()).default({}),
});
export type RenderNotificationTemplatePreviewInput = z.input<typeof RenderNotificationTemplatePreviewInputSchema>;

export const RenderedNotificationTemplateSchema = z.object({
  subject: z.string(),
  body: z.string(),
});
export type RenderedNotificationTemplate = z.infer<typeof RenderedNotificationTemplateSchema>;

/** Re-exported so callers of publishNotificationTemplate don't need a separate import from ../config/config.ts. */
export { ConfigVersionSchema };
export type { ConfigVersion };

/** Maps a raw app.notification_types row (snake_case) to this contract's camelCase shape. */
export function parseNotificationType(row: Record<string, unknown>): NotificationType {
  return NotificationTypeSchema.parse({
    code: row.code,
    name: row.name,
    ownerPrimitiveCode: row.owner_primitive_code,
    registeredBy: row.registered_by,
    createdAt: row.created_at,
  });
}

/** Maps a raw app.notification_preferences row (snake_case) to this contract's camelCase shape. */
export function parseNotificationPreference(row: Record<string, unknown>): NotificationPreference {
  return NotificationPreferenceSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    authUserId: row.auth_user_id,
    notificationTypeCode: row.notification_type_code,
    channel: row.channel,
    enabled: row.enabled,
    updatedAt: row.updated_at,
  });
}

/** Maps a raw app.notifications row (snake_case) to this contract's camelCase shape. */
export function parseNotification(row: Record<string, unknown>): Notification {
  return NotificationSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    configVersionId: row.config_version_id,
    notificationTypeCode: row.notification_type_code,
    recipientAuthUserId: row.recipient_auth_user_id,
    requestedChannel: row.requested_channel,
    effectiveChannel: row.effective_channel,
    locale: row.locale,
    subject: row.subject,
    body: row.body,
    context: row.context,
    status: row.status,
    dedupeKey: row.dedupe_key,
    triggeredByAuthUserId: row.triggered_by_auth_user_id,
    triggeredBy: row.triggered_by,
    readAt: row.read_at,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps a raw app.notification_delivery_attempts row (snake_case) to this contract's camelCase shape. */
export function parseNotificationDeliveryAttempt(row: Record<string, unknown>): NotificationDeliveryAttempt {
  return NotificationDeliveryAttemptSchema.parse({
    id: row.id,
    notificationId: row.notification_id,
    attemptNumber: row.attempt_number,
    status: row.status,
    errorMessage: row.error_message,
    attemptedAt: row.attempted_at,
  });
}
