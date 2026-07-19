import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseNotificationType,
  parseNotificationPreference,
  parseNotification,
  parseNotificationDeliveryAttempt,
  QueueNotificationInputSchema,
  RegisterNotificationTypeInputSchema,
} from "./notification.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "423e4567-e89b-12d3-a456-426614174000";
const PREF_ID = "523e4567-e89b-12d3-a456-426614174000";
const NOTIFICATION_ID = "623e4567-e89b-12d3-a456-426614174000";
const ATTEMPT_ID = "723e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "823e4567-e89b-12d3-a456-426614174000";

describe("parseNotificationType", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const type = parseNotificationType({
      code: "role_assignment_granted",
      name: "Role Assignment Granted",
      owner_primitive_code: "NOTIF",
      registered_by: "platform-core-foundation",
      created_at: "2026-07-19T00:00:00.000Z",
    });
    assert.equal(type.ownerPrimitiveCode, "NOTIF");
  });
});

describe("parseNotificationPreference", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const pref = parseNotificationPreference({
      id: PREF_ID,
      tenant_id: TENANT_ID,
      auth_user_id: ACTOR_ID,
      notification_type_code: "role_assignment_granted",
      channel: "email",
      enabled: false,
      updated_at: "2026-07-19T00:00:00.000Z",
    });
    assert.equal(pref.channel, "email");
    assert.equal(pref.enabled, false);
  });
});

describe("parseNotification", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const notification = parseNotification({
      id: NOTIFICATION_ID,
      tenant_id: TENANT_ID,
      config_version_id: VERSION_ID,
      notification_type_code: "role_assignment_granted",
      recipient_auth_user_id: ACTOR_ID,
      requested_channel: "in_app",
      effective_channel: "in_app",
      locale: "en",
      subject: "You were granted a role",
      body: "You now hold the Manager role.",
      context: { role_name: "Manager" },
      status: "sent",
      dedupe_key: "notif-9001",
      triggered_by_auth_user_id: ACTOR_ID,
      triggered_by: "tenant admin",
      read_at: null,
      created_at: "2026-07-19T00:00:00.000Z",
      updated_at: "2026-07-19T00:00:00.000Z",
    });
    assert.equal(notification.status, "sent");
    assert.deepEqual(notification.context, { role_name: "Manager" });
  });
});

describe("parseNotificationDeliveryAttempt", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const attempt = parseNotificationDeliveryAttempt({
      id: ATTEMPT_ID,
      notification_id: NOTIFICATION_ID,
      attempt_number: 1,
      status: "failed",
      error_message: "provider timeout",
      attempted_at: "2026-07-19T00:00:00.000Z",
    });
    assert.equal(attempt.status, "failed");
    assert.equal(attempt.attemptNumber, 1);
  });
});

describe("QueueNotificationInputSchema", () => {
  test("defaults locale to en and context to {}", () => {
    const parsed = QueueNotificationInputSchema.parse({
      configVersionId: VERSION_ID,
      tenantId: TENANT_ID,
      notificationTypeCode: "role_assignment_granted",
      recipientAuthUserId: ACTOR_ID,
      channel: "in_app",
      dedupeKey: "notif-9001",
      actorAuthUserId: ACTOR_ID,
      triggeredBy: "tenant admin",
    });
    assert.equal(parsed.locale, "en");
    assert.deepEqual(parsed.context, {});
  });

  test("rejects an unknown channel", () => {
    assert.throws(() =>
      QueueNotificationInputSchema.parse({
        configVersionId: VERSION_ID,
        tenantId: TENANT_ID,
        notificationTypeCode: "role_assignment_granted",
        recipientAuthUserId: ACTOR_ID,
        channel: "sms",
        dedupeKey: "notif-9001",
        actorAuthUserId: ACTOR_ID,
        triggeredBy: "tenant admin",
      }),
    );
  });
});

describe("RegisterNotificationTypeInputSchema", () => {
  test("parses a well-formed input", () => {
    const parsed = RegisterNotificationTypeInputSchema.parse({
      code: "role_assignment_granted",
      name: "Role Assignment Granted",
      ownerPrimitiveCode: "NOTIF",
      actorAuthUserId: ACTOR_ID,
      registeredBy: "tester",
    });
    assert.equal(parsed.code, "role_assignment_granted");
  });
});
