/**
 * Notification engine mutation primitives (PLT-127, CG-S6-PLT-024). Thin, typed
 * wrappers around app.register_notification_type / app.publish_notification_template /
 * app.set_notification_preference / app.queue_notification /
 * app.record_notification_delivery_attempt / app.mark_notification_read
 * (supabase/migrations/20260719130000_create_notification_engine.sql).
 * app.mark_notification_read is authenticated-callable (a recipient marking their own
 * notification read); every other mutation here is service_role-only (see the
 * migration's own grant comment).
 */

import {
  RegisterNotificationTypeInputSchema,
  PublishNotificationTemplateInputSchema,
  SetNotificationPreferenceInputSchema,
  QueueNotificationInputSchema,
  RecordNotificationDeliveryAttemptInputSchema,
  MarkNotificationReadInputSchema,
  ConfigVersionSchema,
  parseNotificationType,
  parseNotificationPreference,
  parseNotification,
  parseNotificationDeliveryAttempt,
  type RegisterNotificationTypeInput,
  type PublishNotificationTemplateInput,
  type SetNotificationPreferenceInput,
  type QueueNotificationInput,
  type RecordNotificationDeliveryAttemptInput,
  type MarkNotificationReadInput,
  type NotificationType,
  type NotificationPreference,
  type Notification,
  type NotificationDeliveryAttempt,
  type ConfigVersion,
} from "../contracts/notification/notification.ts";
import { parseConfigVersion } from "../contracts/config/config.ts";

export interface NotificationMutationRpcClient {
  rpc(
    fn:
      | "register_notification_type"
      | "publish_notification_template"
      | "set_notification_preference"
      | "queue_notification"
      | "record_notification_delivery_attempt"
      | "mark_notification_read",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const NOTIFICATION_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "notification_missing_channels",
  "notification_invalid_channel",
  "notification_invalid_locale",
  "notification_missing_templates",
  "notification_missing_default_template",
  "notification_missing_subject",
  "notification_missing_body",
  "notification_invalid_template_tokens",
  "notification_template_not_published",
  "notification_recipient_unauthorized",
  "notification_channel_not_supported",
  "notification_not_found",
  "notification_invalid_attempt_status",
  "notification_unsafe_context_value",
  "notification_unsafe_link",
] as const;
type KnownNotificationMutationErrorCode = (typeof NOTIFICATION_KNOWN_MUTATION_ERROR_CODES)[number];
export type NotificationMutationErrorCode = KnownNotificationMutationErrorCode | "mutation_failed" | "invalid_response";

export class NotificationMutationError extends Error {
  readonly code: NotificationMutationErrorCode;

  constructor(code: NotificationMutationErrorCode, message: string) {
    super(message);
    this.name = "NotificationMutationError";
    this.code = code;
  }
}

function classifyError(message: string): NotificationMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (NOTIFICATION_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownNotificationMutationErrorCode)
    : "mutation_failed";
}

/** Idempotent -- Supreme-Admin-only. Also mints a dedicated notification:<code> config_type. */
export async function registerNotificationType(client: NotificationMutationRpcClient, input: RegisterNotificationTypeInput): Promise<NotificationType> {
  const parsedInput = RegisterNotificationTypeInputSchema.parse(input);
  const { data, error } = await client.rpc("register_notification_type", {
    p_code: parsedInput.code,
    p_name: parsedInput.name,
    p_owner_primitive_code: parsedInput.ownerPrimitiveCode,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_registered_by: parsedInput.registeredBy,
  });
  if (error) {
    throw new NotificationMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new NotificationMutationError("invalid_response", "register_notification_type returned no row");
  }
  return parseNotificationType(data as Record<string, unknown>);
}

/** Runs the structural validation gate (bounded channels, real locale codes, balanced {{ }} tokens), then supersedes the prior published template. */
export async function publishNotificationTemplate(client: NotificationMutationRpcClient, input: PublishNotificationTemplateInput): Promise<ConfigVersion> {
  const parsedInput = PublishNotificationTemplateInputSchema.parse(input);
  const { data, error } = await client.rpc("publish_notification_template", {
    p_version_id: parsedInput.versionId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_effective_from: parsedInput.effectiveFrom,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new NotificationMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new NotificationMutationError("invalid_response", "publish_notification_template returned no row");
  }
  return ConfigVersionSchema.parse(parseConfigVersion(data as Record<string, unknown>));
}

/** Self-service by default; a tenant's own support-grant authority may set it on a user's behalf. */
export async function setNotificationPreference(client: NotificationMutationRpcClient, input: SetNotificationPreferenceInput): Promise<NotificationPreference> {
  const parsedInput = SetNotificationPreferenceInputSchema.parse(input);
  const { data, error } = await client.rpc("set_notification_preference", {
    p_tenant_id: parsedInput.tenantId,
    p_auth_user_id: parsedInput.authUserId,
    p_notification_type_code: parsedInput.notificationTypeCode,
    p_channel: parsedInput.channel,
    p_enabled: parsedInput.enabled,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new NotificationMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new NotificationMutationError("invalid_response", "set_notification_preference returned no row");
  }
  return parseNotificationPreference(data as Record<string, unknown>);
}

/** Idempotent on (tenant, notificationTypeCode, recipient, requestedChannel, dedupeKey). Refuses to queue for a recipient who is not currently an active tenant member. Falls back to in_app when the requested channel is disabled by preference and in_app is both allowed and not itself disabled; otherwise records status=skipped rather than dropping silently. */
export async function queueNotification(client: NotificationMutationRpcClient, input: QueueNotificationInput): Promise<Notification> {
  const parsedInput = QueueNotificationInputSchema.parse(input);
  const { data, error } = await client.rpc("queue_notification", {
    p_config_version_id: parsedInput.configVersionId,
    p_tenant_id: parsedInput.tenantId,
    p_notification_type_code: parsedInput.notificationTypeCode,
    p_recipient_auth_user_id: parsedInput.recipientAuthUserId,
    p_channel: parsedInput.channel,
    p_locale: parsedInput.locale,
    p_context: parsedInput.context,
    p_dedupe_key: parsedInput.dedupeKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_triggered_by: parsedInput.triggeredBy,
  });
  if (error) {
    throw new NotificationMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new NotificationMutationError("invalid_response", "queue_notification returned no row");
  }
  return parseNotification(data as Record<string, unknown>);
}

/** The bounded adapter interface a real external-provider integration calls to report one delivery attempt's outcome against a non-in_app notification -- this repository never calls it against a fabricated provider itself. */
export async function recordNotificationDeliveryAttempt(client: NotificationMutationRpcClient, input: RecordNotificationDeliveryAttemptInput): Promise<NotificationDeliveryAttempt> {
  const parsedInput = RecordNotificationDeliveryAttemptInputSchema.parse(input);
  const { data, error } = await client.rpc("record_notification_delivery_attempt", {
    p_notification_id: parsedInput.notificationId,
    p_status: parsedInput.status,
    p_error_message: parsedInput.errorMessage,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new NotificationMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new NotificationMutationError("invalid_response", "record_notification_delivery_attempt returned no row");
  }
  return parseNotificationDeliveryAttempt(data as Record<string, unknown>);
}

/** Only the recipient themselves (or Supreme) may mark their own notification read. Idempotent -- read_at is set only if it was previously null. */
export async function markNotificationRead(client: NotificationMutationRpcClient, input: MarkNotificationReadInput): Promise<Notification> {
  const parsedInput = MarkNotificationReadInputSchema.parse(input);
  const { data, error } = await client.rpc("mark_notification_read", {
    p_notification_id: parsedInput.notificationId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new NotificationMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new NotificationMutationError("invalid_response", "mark_notification_read returned no row");
  }
  return parseNotification(data as Record<string, unknown>);
}
