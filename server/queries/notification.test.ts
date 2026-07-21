import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  listNotificationsForRecipient,
  countUnreadNotifications,
  getNotificationPreferences,
  renderNotificationTemplatePreview,
  NotificationQueryError,
  type NotificationQueryRpcClient,
} from "./notification.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "423e4567-e89b-12d3-a456-426614174000";
const NOTIFICATION_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "823e4567-e89b-12d3-a456-426614174000";

function fakeClient(
  response: { data: unknown; error: { message: string } | null },
): NotificationQueryRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn, args) {
      calls.push({ fn, args });
      return response;
    },
  };
}

describe("listNotificationsForRecipient", () => {
  test("calls list_notifications_for_recipient with the exact snake_case params and maps rows", async () => {
    const client = fakeClient({
      data: [
        {
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
          context: {},
          status: "sent",
          dedupe_key: "notif-9001",
          triggered_by_auth_user_id: ACTOR_ID,
          triggered_by: "tenant admin",
          read_at: null,
          created_at: "2026-07-19T00:00:00.000Z",
          updated_at: "2026-07-19T00:00:00.000Z",
        },
      ],
      error: null,
    });

    const notifications = await listNotificationsForRecipient(client, { tenantId: TENANT_ID, recipientAuthUserId: ACTOR_ID, actorAuthUserId: ACTOR_ID, unreadOnly: true });
    assert.deepEqual(client.calls[0]?.args, { p_tenant_id: TENANT_ID, p_recipient_auth_user_id: ACTOR_ID, p_actor_auth_user_id: ACTOR_ID, p_unread_only: true });
    assert.equal(notifications.length, 1);
  });

  test("throws NotificationQueryError on an rpc error", async () => {
    const client = fakeClient({ data: null, error: { message: "insufficient_authority: identity x may not list another identity's notifications" } });
    await assert.rejects(() => listNotificationsForRecipient(client, { tenantId: TENANT_ID, recipientAuthUserId: ACTOR_ID, actorAuthUserId: ACTOR_ID }));
  });
});

describe("countUnreadNotifications", () => {
  test("calls count_unread_notifications and returns the count", async () => {
    const client = fakeClient({ data: 3, error: null });
    const count = await countUnreadNotifications(client, { tenantId: TENANT_ID, recipientAuthUserId: ACTOR_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(count, 3);
  });

  test("throws NotificationQueryError if data is not numeric", async () => {
    const client = fakeClient({ data: null, error: null });
    await assert.rejects(() => countUnreadNotifications(client, { tenantId: TENANT_ID, recipientAuthUserId: ACTOR_ID, actorAuthUserId: ACTOR_ID }));
  });
});

describe("getNotificationPreferences", () => {
  test("calls get_notification_preferences and maps rows", async () => {
    const client = fakeClient({
      data: [
        { id: "923e4567-e89b-12d3-a456-426614174000", tenant_id: TENANT_ID, auth_user_id: ACTOR_ID, notification_type_code: "role_assignment_granted", channel: "email", enabled: false, updated_at: "2026-07-19T00:00:00.000Z" },
      ],
      error: null,
    });
    const prefs = await getNotificationPreferences(client, { tenantId: TENANT_ID, authUserId: ACTOR_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(prefs.length, 1);
    assert.equal(prefs[0]?.enabled, false);
  });
});

describe("renderNotificationTemplatePreview", () => {
  test("calls render_notification_template with the exact snake_case params", async () => {
    const client = fakeClient({ data: { subject: "You were granted a role", body: "You now hold the Manager role." }, error: null });
    const rendered = await renderNotificationTemplatePreview(client, { configVersionId: VERSION_ID, locale: "en", context: { role_name: "Manager" } });

    assert.deepEqual(client.calls[0]?.args, { p_config_version_id: VERSION_ID, p_locale: "en", p_context: { role_name: "Manager" } });
    assert.equal(rendered.subject, "You were granted a role");
  });

  test("throws NotificationQueryError on an unsafe context value", async () => {
    const client = fakeClient({ data: null, error: { message: "notification_unsafe_context_value: context key note contains an angle bracket, refusing to render" } });
    await assert.rejects(() => renderNotificationTemplatePreview(client, { configVersionId: VERSION_ID, locale: "en", context: { note: "<script>" } }));
  });
});
