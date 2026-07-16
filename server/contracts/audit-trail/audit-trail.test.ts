import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { AuditLogSchema, CaptureAuditEventInputSchema, parseAuditLog } from "./audit-trail.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const RESOURCE_ID = "423e4567-e89b-12d3-a456-426614174000";

const ROW = {
  id: "523e4567-e89b-12d3-a456-426614174000",
  correlation_id: "623e4567-e89b-12d3-a456-426614174000",
  tenant_id: TENANT_ID,
  actor_auth_user_id: ACTOR_ID,
  actor_label: "tenant admin",
  action: "update",
  resource_type: "app.tenants",
  resource_id: RESOURCE_ID,
  result: "success",
  reason: "routine update",
  before_value: { display_name: "Old" },
  after_value: { display_name: "New" },
  occurred_at: "2026-07-16T00:00:00.000Z",
  legal_hold: false,
  legal_hold_reason: null,
};

describe("parseAuditLog", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const log = parseAuditLog(ROW);
    assert.equal(log.correlationId, "623e4567-e89b-12d3-a456-426614174000");
    assert.equal(log.actorLabel, "tenant admin");
    assert.deepEqual(log.beforeValue, { display_name: "Old" });
    assert.equal(log.legalHold, false);
  });

  test("accepts a null tenant_id and null actor_auth_user_id (platform-wide/system events)", () => {
    const log = parseAuditLog({ ...ROW, tenant_id: null, actor_auth_user_id: null });
    assert.equal(log.tenantId, null);
    assert.equal(log.actorAuthUserId, null);
  });

  test("rejects a row with an unknown result value (defense against a future untyped enum value)", () => {
    assert.throws(() => parseAuditLog({ ...ROW, result: "maybe" }));
  });
});

describe("AuditLogSchema", () => {
  test("requires actorLabel to be present even when actorAuthUserId is null", () => {
    const log = parseAuditLog(ROW);
    assert.throws(() => AuditLogSchema.parse({ ...log, actorLabel: undefined }));
  });
});

describe("CaptureAuditEventInputSchema", () => {
  test("defaults reason/beforeValue/afterValue/correlationId to null", () => {
    const parsed = CaptureAuditEventInputSchema.parse({
      tenantId: TENANT_ID,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
      action: "create",
      resourceType: "app.org_units",
      resourceId: null,
      result: "success",
    });
    assert.equal(parsed.reason, null);
    assert.equal(parsed.beforeValue, null);
    assert.equal(parsed.afterValue, null);
    assert.equal(parsed.correlationId, null);
  });

  test("rejects an invalid result value", () => {
    assert.throws(() =>
      CaptureAuditEventInputSchema.parse({
        tenantId: TENANT_ID,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "tester",
        action: "create",
        resourceType: "app.org_units",
        resourceId: null,
        result: "maybe",
      }),
    );
  });

  /**
   * Mass-assignment protection proof, mirroring PLT-114/PLT-115's own contract tests:
   * an attacker-supplied field forging a captured id/occurred_at/legal_hold state must
   * never survive .parse() -- this is the client-side input contract, not the server
   * row shape, so it never even has a slot for those fields to land in.
   */
  test("strips unrecognized fields such as a forged id or legal_hold state", () => {
    const parsed = CaptureAuditEventInputSchema.parse({
      tenantId: TENANT_ID,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
      action: "create",
      resourceType: "app.org_units",
      resourceId: null,
      result: "success",
      id: "923e4567-e89b-12d3-a456-426614174000",
      legal_hold: true,
    } as never);
    assert.equal((parsed as Record<string, unknown>).id, undefined);
    assert.equal((parsed as Record<string, unknown>).legal_hold, undefined);
  });
});
