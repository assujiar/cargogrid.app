/**
 * Notification read/preview queries (PLT-127, CG-S6-PLT-024). Thin, typed wrappers
 * around app.list_notifications_for_recipient / app.count_unread_notifications /
 * app.get_notification_preferences / app.render_notification_template
 * (supabase/migrations/20260719130000_create_notification_engine.sql) -- the reusable
 * in-app inbox/count/preference view models Prompt 127 §15 calls for.
 */

import {
  ListNotificationsForRecipientInputSchema,
  CountUnreadNotificationsInputSchema,
  GetNotificationPreferencesInputSchema,
  RenderNotificationTemplatePreviewInputSchema,
  parseNotification,
  parseNotificationPreference,
  RenderedNotificationTemplateSchema,
  type ListNotificationsForRecipientInput,
  type CountUnreadNotificationsInput,
  type GetNotificationPreferencesInput,
  type RenderNotificationTemplatePreviewInput,
  type Notification,
  type NotificationPreference,
  type RenderedNotificationTemplate,
} from "../contracts/notification/notification.ts";

export interface NotificationQueryRpcClient {
  rpc(
    fn: "list_notifications_for_recipient" | "count_unread_notifications" | "get_notification_preferences" | "render_notification_template",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class NotificationQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "NotificationQueryError";
  }
}

/** The in-app inbox view model. Authority-gated -- only the recipient themselves (or Supreme) may list their own notifications. */
export async function listNotificationsForRecipient(client: NotificationQueryRpcClient, input: ListNotificationsForRecipientInput): Promise<Notification[]> {
  const parsedInput = ListNotificationsForRecipientInputSchema.parse(input);
  const { data, error } = await client.rpc("list_notifications_for_recipient", {
    p_tenant_id: parsedInput.tenantId,
    p_recipient_auth_user_id: parsedInput.recipientAuthUserId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_unread_only: parsedInput.unreadOnly,
  });
  if (error) {
    throw new NotificationQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new NotificationQueryError("list_notifications_for_recipient returned a non-array result");
  }
  return data.map((row) => parseNotification(row as Record<string, unknown>));
}

/** The in-app badge-count view model. */
export async function countUnreadNotifications(client: NotificationQueryRpcClient, input: CountUnreadNotificationsInput): Promise<number> {
  const parsedInput = CountUnreadNotificationsInputSchema.parse(input);
  const { data, error } = await client.rpc("count_unread_notifications", {
    p_tenant_id: parsedInput.tenantId,
    p_recipient_auth_user_id: parsedInput.recipientAuthUserId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new NotificationQueryError(error.message);
  }
  if (typeof data !== "number") {
    throw new NotificationQueryError("count_unread_notifications returned a non-numeric result");
  }
  return data;
}

/** The reusable preference view model. */
export async function getNotificationPreferences(client: NotificationQueryRpcClient, input: GetNotificationPreferencesInput): Promise<NotificationPreference[]> {
  const parsedInput = GetNotificationPreferencesInputSchema.parse(input);
  const { data, error } = await client.rpc("get_notification_preferences", {
    p_tenant_id: parsedInput.tenantId,
    p_auth_user_id: parsedInput.authUserId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new NotificationQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new NotificationQueryError("get_notification_preferences returned a non-array result");
  }
  return data.map((row) => parseNotificationPreference(row as Record<string, unknown>));
}

/** A live template preview -- runs the exact same rendering (and unsafe-context/unsafe-link rejection) app.queue_notification() itself performs, without ever queuing or writing anything. */
export async function renderNotificationTemplatePreview(client: NotificationQueryRpcClient, input: RenderNotificationTemplatePreviewInput): Promise<RenderedNotificationTemplate> {
  const parsedInput = RenderNotificationTemplatePreviewInputSchema.parse(input);
  const { data, error } = await client.rpc("render_notification_template", {
    p_config_version_id: parsedInput.configVersionId,
    p_locale: parsedInput.locale,
    p_context: parsedInput.context,
  });
  if (error) {
    throw new NotificationQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new NotificationQueryError("render_notification_template returned no row");
  }
  return RenderedNotificationTemplateSchema.parse(row);
}
