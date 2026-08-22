import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { parseAuditLog, parseAuditExportRequest, SearchAuditLogsInputSchema, RequestAuditExportInputSchema } from "./advanced-audit.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const LOG_ID = "423e4567-e89b-12d3-a456-426614174000";

describe("parseAuditLog", () => {
  test("round-trips a session-linked event", () => {
    const log = parseAuditLog({
      id: LOG_ID, correlation_id: LOG_ID, tenant_id: TENANT_ID, actor_auth_user_id: ACTOR_ID, actor_label: "admin1",
      action: "test_action", resource_type: "app.some_table", resource_id: null, result: "success", reason: null,
      before_value: null, after_value: null, occurred_at: "2026-08-22T00:00:00.000Z", legal_hold: false, legal_hold_reason: null,
      support_access_grant_id: LOG_ID,
    });
    assert.equal(log.supportAccessGrantId, LOG_ID);
  });

  test("rejects an unrecognized result", () => {
    assert.throws(() =>
      parseAuditLog({
        id: LOG_ID, correlation_id: LOG_ID, tenant_id: TENANT_ID, actor_auth_user_id: ACTOR_ID, actor_label: "admin1",
        action: "test_action", resource_type: "app.some_table", resource_id: null, result: "not-a-real-result", reason: null,
        before_value: null, after_value: null, occurred_at: "2026-08-22T00:00:00.000Z", legal_hold: false, legal_hold_reason: null,
        support_access_grant_id: null,
      }),
    );
  });
});

describe("parseAuditExportRequest", () => {
  test("round-trips a pending request", () => {
    const request = parseAuditExportRequest({
      id: LOG_ID, tenant_id: TENANT_ID, requested_by_auth_user_id: ACTOR_ID, requested_by: "admin1",
      filters: {}, status: "pending", result_row_count: null, result_payload: null, failure_reason: null,
      requested_at: "2026-08-22T00:00:00.000Z", completed_at: null, expires_at: null,
    });
    assert.equal(request.status, "pending");
  });
});

describe("input schemas", () => {
  test("SearchAuditLogsInputSchema rejects an out-of-range limit", () => {
    assert.throws(() =>
      SearchAuditLogsInputSchema.parse({
        tenantId: TENANT_ID, actorAuthUserIdFilter: null, actionFilter: null, resourceTypeFilter: null,
        resultFilter: null, supportAccessGrantIdFilter: null, occurredAfter: null, occurredBefore: null,
        requesterAuthUserId: ACTOR_ID, limit: 9999,
      }),
    );
  });

  test("RequestAuditExportInputSchema rejects an empty actorLabel", () => {
    assert.throws(() => RequestAuditExportInputSchema.parse({ tenantId: TENANT_ID, filters: {}, actorAuthUserId: ACTOR_ID, actorLabel: "" }));
  });
});
