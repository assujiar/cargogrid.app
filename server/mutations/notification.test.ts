import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  registerNotificationType,
  publishNotificationTemplate,
  setNotificationPreference,
  queueNotification,
  recordNotificationDeliveryAttempt,
  markNotificationRead,
  NotificationMutationError,
  type NotificationMutationRpcClient,
} from "./notification.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const OBJECT_ID = "323e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "423e4567-e89b-12d3-a456-426614174000";
const PREF_ID = "523e4567-e89b-12d3-a456-426614174000";
const NOTIFICATION_ID = "623e4567-e89b-12d3-a456-426614174000";
const ATTEMPT_ID = "723e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "823e4567-e89b-12d3-a456-426614174000";

const VALID_TYPE_ROW = {
  code: "role_assignment_granted",
  name: "Role Assignment Granted",
  owner_primitive_code: "NOTIF",
  registered_by: "platform-core-foundation",
  created_at: "2026-07-19T00:00:00.000Z",
};

const VALID_VERSION_ROW = {
  id: VERSION_ID,
  config_object_id: OBJECT_ID,
  version_number: 1,
  status: "published",
  effective_from: "2026-07-19T00:00:00.000Z",
  effective_to: null,
  cloned_from_version_id: null,
  rollback_of_version_id: null,
  created_by: "tenant admin",
  published_by: "tenant admin",
  published_at: "2026-07-19T00:00:00.000Z",
  archived_at: null,
  archived_reason: null,
  record_version: 2,
  created_at: "2026-07-19T00:00:00.000Z",
  updated_at: "2026-07-19T00:00:00.000Z",
};

const VALID_PREF_ROW = {
  id: PREF_ID,
  tenant_id: TENANT_ID,
  auth_user_id: ACTOR_ID,
  notification_type_code: "role_assignment_granted",
  channel: "email",
  enabled: false,
  updated_at: "2026-07-19T00:00:00.000Z",
};

const VALID_NOTIFICATION_ROW = {
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
};

const VALID_ATTEMPT_ROW = {
  id: ATTEMPT_ID,
  notification_id: NOTIFICATION_ID,
  attempt_number: 1,
  status: "failed",
  error_message: "provider timeout",
  attempted_at: "2026-07-19T00:00:00.000Z",
};

function fakeClient(
  response: { data: unknown; error: { message: string } | null },
): NotificationMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn, args) {
      calls.push({ fn, args });
      return response;
    },
  };
}

describe("registerNotificationType", () => {
  test("calls register_notification_type with the exact snake_case params", async () => {
    const client = fakeClient({ data: VALID_TYPE_ROW, error: null });
    await registerNotificationType(client, { code: "role_assignment_granted", name: "Role Assignment Granted", ownerPrimitiveCode: "NOTIF", actorAuthUserId: ACTOR_ID, registeredBy: "tester" });

    assert.deepEqual(client.calls[0]?.args, {
      p_code: "role_assignment_granted",
      p_name: "Role Assignment Granted",
      p_owner_primitive_code: "NOTIF",
      p_actor_auth_user_id: ACTOR_ID,
      p_registered_by: "tester",
    });
  });

  test("wraps an insufficient_authority error", async () => {
    const client = fakeClient({ data: null, error: { message: "insufficient_authority: only Supreme Admin may register a notification type" } });
    await assert.rejects(
      () => registerNotificationType(client, { code: "x", name: "X", ownerPrimitiveCode: "NOTIF", actorAuthUserId: ACTOR_ID, registeredBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof NotificationMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });
});

describe("publishNotificationTemplate", () => {
  test("calls publish_notification_template and returns the published version row", async () => {
    const client = fakeClient({ data: VALID_VERSION_ROW, error: null });
    const version = await publishNotificationTemplate(client, { versionId: VERSION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" });
    assert.equal(version.status, "published");
  });

  test("wraps a notification_invalid_template_tokens error", async () => {
    const client = fakeClient({ data: null, error: { message: "notification_invalid_template_tokens: locale en's subject has unbalanced {{ }} token braces" } });
    await assert.rejects(
      () => publishNotificationTemplate(client, { versionId: VERSION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" }),
      (err: unknown) => {
        assert.ok(err instanceof NotificationMutationError);
        assert.equal(err.code, "notification_invalid_template_tokens");
        return true;
      },
    );
  });
});

describe("setNotificationPreference", () => {
  test("calls set_notification_preference with the exact snake_case params", async () => {
    const client = fakeClient({ data: VALID_PREF_ROW, error: null });
    const pref = await setNotificationPreference(client, {
      tenantId: TENANT_ID,
      authUserId: ACTOR_ID,
      notificationTypeCode: "role_assignment_granted",
      channel: "email",
      enabled: false,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tenant user",
    });

    assert.deepEqual(client.calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_auth_user_id: ACTOR_ID,
      p_notification_type_code: "role_assignment_granted",
      p_channel: "email",
      p_enabled: false,
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "tenant user",
    });
    assert.equal(pref.enabled, false);
  });
});

describe("queueNotification", () => {
  test("calls queue_notification with the exact snake_case params", async () => {
    const client = fakeClient({ data: VALID_NOTIFICATION_ROW, error: null });
    const notification = await queueNotification(client, {
      configVersionId: VERSION_ID,
      tenantId: TENANT_ID,
      notificationTypeCode: "role_assignment_granted",
      recipientAuthUserId: ACTOR_ID,
      channel: "in_app",
      locale: "en",
      context: { role_name: "Manager" },
      dedupeKey: "notif-9001",
      actorAuthUserId: ACTOR_ID,
      triggeredBy: "tenant admin",
    });

    assert.deepEqual(client.calls[0]?.args, {
      p_config_version_id: VERSION_ID,
      p_tenant_id: TENANT_ID,
      p_notification_type_code: "role_assignment_granted",
      p_recipient_auth_user_id: ACTOR_ID,
      p_channel: "in_app",
      p_locale: "en",
      p_context: { role_name: "Manager" },
      p_dedupe_key: "notif-9001",
      p_actor_auth_user_id: ACTOR_ID,
      p_triggered_by: "tenant admin",
    });
    assert.equal(notification.status, "sent");
  });

  test("wraps a notification_recipient_unauthorized error", async () => {
    const client = fakeClient({ data: null, error: { message: "notification_recipient_unauthorized: identity x is not an active member of tenant y -- refusing to queue" } });
    await assert.rejects(
      () =>
        queueNotification(client, {
          configVersionId: VERSION_ID,
          tenantId: TENANT_ID,
          notificationTypeCode: "role_assignment_granted",
          recipientAuthUserId: ACTOR_ID,
          channel: "in_app",
          dedupeKey: "notif-9001",
          actorAuthUserId: ACTOR_ID,
          triggeredBy: "tenant admin",
        }),
      (err: unknown) => {
        assert.ok(err instanceof NotificationMutationError);
        assert.equal(err.code, "notification_recipient_unauthorized");
        return true;
      },
    );
  });
});

describe("recordNotificationDeliveryAttempt", () => {
  test("calls record_notification_delivery_attempt with the exact snake_case params", async () => {
    const client = fakeClient({ data: VALID_ATTEMPT_ROW, error: null });
    const attempt = await recordNotificationDeliveryAttempt(client, { notificationId: NOTIFICATION_ID, status: "failed", errorMessage: "provider timeout", actorAuthUserId: ACTOR_ID, actorLabel: "system" });

    assert.deepEqual(client.calls[0]?.args, {
      p_notification_id: NOTIFICATION_ID,
      p_status: "failed",
      p_error_message: "provider timeout",
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "system",
    });
    assert.equal(attempt.status, "failed");
  });
});

describe("markNotificationRead", () => {
  test("calls mark_notification_read and returns the updated notification", async () => {
    const readRow = { ...VALID_NOTIFICATION_ROW, read_at: "2026-07-19T01:00:00.000Z" };
    const client = fakeClient({ data: readRow, error: null });
    const notification = await markNotificationRead(client, { notificationId: NOTIFICATION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant user" });
    assert.equal(notification.readAt, "2026-07-19T01:00:00.000Z");
  });

  test("wraps an insufficient_authority error", async () => {
    const client = fakeClient({ data: null, error: { message: "insufficient_authority: identity x may not mark another identity's notification read" } });
    await assert.rejects(
      () => markNotificationRead(client, { notificationId: NOTIFICATION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant user" }),
      (err: unknown) => {
        assert.ok(err instanceof NotificationMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });
});
