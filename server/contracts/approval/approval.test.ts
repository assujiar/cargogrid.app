import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseApprovalRequest,
  parseApprovalRequestStep,
  parseApprovalDelegation,
  parseApprovalRequestHistoryEntry,
  RequestApprovalInputSchema,
  CreateApprovalDelegationInputSchema,
} from "./approval.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "423e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const STEP_ID = "723e4567-e89b-12d3-a456-426614174000";
const ROLE_ID = "823e4567-e89b-12d3-a456-426614174000";

describe("parseApprovalRequest", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const request = parseApprovalRequest({
      id: REQUEST_ID,
      tenant_id: TENANT_ID,
      config_version_id: VERSION_ID,
      entity_type: "generic",
      entity_id: null,
      pattern: "sequential",
      status: "pending",
      idempotency_key: "req-9001",
      requested_by_auth_user_id: ACTOR_ID,
      requested_by: "tenant user",
      started_at: "2026-07-19T00:00:00.000Z",
      ended_at: null,
      ended_reason: null,
      record_version: 1,
      created_at: "2026-07-19T00:00:00.000Z",
      updated_at: "2026-07-19T00:00:00.000Z",
    });
    assert.equal(request.status, "pending");
    assert.equal(request.pattern, "sequential");
  });
});

describe("parseApprovalRequestStep", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const step = parseApprovalRequestStep({
      id: STEP_ID,
      request_id: REQUEST_ID,
      step_order: 1,
      approver_type: "role",
      role_id: ROLE_ID,
      specific_user_id: null,
      required_approvals: 1,
      approvals_count: 0,
      status: "active",
      created_at: "2026-07-19T00:00:00.000Z",
      updated_at: "2026-07-19T00:00:00.000Z",
    });
    assert.equal(step.approverType, "role");
    assert.equal(step.roleId, ROLE_ID);
  });
});

describe("parseApprovalDelegation", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const delegation = parseApprovalDelegation({
      id: "923e4567-e89b-12d3-a456-426614174000",
      tenant_id: TENANT_ID,
      delegator_auth_user_id: ACTOR_ID,
      delegate_auth_user_id: ROLE_ID,
      scope: "all",
      role_id: null,
      starts_at: "2026-07-19T00:00:00.000Z",
      expires_at: "2026-08-19T00:00:00.000Z",
      created_by: "tenant admin",
      created_at: "2026-07-19T00:00:00.000Z",
      revoked_at: null,
      revoked_reason: null,
    });
    assert.equal(delegation.scope, "all");
    assert.equal(delegation.revokedAt, null);
  });
});

describe("parseApprovalRequestHistoryEntry", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const entry = parseApprovalRequestHistoryEntry({
      step_id: STEP_ID,
      step_order: 1,
      approver_type: "role",
      step_status: "approved",
      decision_id: "a23e4567-e89b-12d3-a456-426614174000",
      actor_auth_user_id: ACTOR_ID,
      actor_label: "tenant user",
      decision: "approved",
      reason: null,
      decided_at: "2026-07-19T00:00:00.000Z",
    });
    assert.equal(entry.decision, "approved");
    assert.equal(entry.stepStatus, "approved");
  });
});

describe("RequestApprovalInputSchema", () => {
  test("defaults entityType to generic and entityId to null", () => {
    const parsed = RequestApprovalInputSchema.parse({
      configVersionId: VERSION_ID,
      tenantId: TENANT_ID,
      idempotencyKey: "req-9001",
      actorAuthUserId: ACTOR_ID,
      requestedBy: "tenant user",
    });
    assert.equal(parsed.entityType, "generic");
    assert.equal(parsed.entityId, null);
  });
});

describe("CreateApprovalDelegationInputSchema", () => {
  test("defaults scope to all and roleId/startsAt to null", () => {
    const parsed = CreateApprovalDelegationInputSchema.parse({
      tenantId: TENANT_ID,
      delegatorAuthUserId: ACTOR_ID,
      delegateAuthUserId: ROLE_ID,
      expiresAt: "2026-08-19T00:00:00.000Z",
      actorAuthUserId: ACTOR_ID,
      createdBy: "tenant admin",
    });
    assert.equal(parsed.scope, "all");
    assert.equal(parsed.roleId, null);
    assert.equal(parsed.startsAt, null);
  });

  test("rejects an unknown scope", () => {
    assert.throws(() =>
      CreateApprovalDelegationInputSchema.parse({
        tenantId: TENANT_ID,
        delegatorAuthUserId: ACTOR_ID,
        delegateAuthUserId: ROLE_ID,
        scope: "everything",
        expiresAt: "2026-08-19T00:00:00.000Z",
        actorAuthUserId: ACTOR_ID,
        createdBy: "tenant admin",
      }),
    );
  });
});
