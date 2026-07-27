import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseResourceAssignment,
  parseAssignmentCandidate,
  AssignResourceInputSchema,
  ReassignResourceInputSchema,
  HoldResourceAssignmentInputSchema,
} from "./resource-assignment.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ASSIGNMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const RESOURCE_ID = "623e4567-e89b-12d3-a456-426614174000";

describe("parseResourceAssignment", () => {
  test("maps a real row into camelCase, defaulting nullable fields", () => {
    const assignment = parseResourceAssignment({
      id: ASSIGNMENT_ID,
      tenant_id: TENANT_ID,
      shipment_order_id: SHIPMENT_ID,
      role: "vendor",
      resource_id: RESOURCE_ID,
      resource_snapshot: { code: "VEND-1", name: "Contoso Trucking" },
      status: "active",
      is_current: true,
      effective_from: "2026-07-27T00:00:00.000Z",
      effective_to: null,
      reason: null,
      superseded_by_id: null,
      record_version: 1,
      created_by: "rep",
      created_at: "2026-07-27T00:00:00.000Z",
      updated_at: "2026-07-27T00:00:00.000Z",
    });
    assert.equal(assignment.role, "vendor");
    assert.equal(assignment.resourceSnapshot.code, "VEND-1");
    assert.equal(assignment.reason, null);
    assert.equal(assignment.supersededById, null);
  });

  test("never accepts a snapshot beyond {code, name} -- rejects an attributes leak", () => {
    assert.throws(() =>
      parseResourceAssignment({
        id: ASSIGNMENT_ID,
        tenant_id: TENANT_ID,
        shipment_order_id: SHIPMENT_ID,
        role: "driver",
        resource_id: RESOURCE_ID,
        resource_snapshot: { code: "DRV-1", name: "Budi Santoso", national_id: "3271000000000001" },
        status: "active",
        is_current: true,
        effective_from: "2026-07-27T00:00:00.000Z",
        effective_to: null,
        reason: null,
        superseded_by_id: null,
        record_version: 1,
        created_by: "rep",
        created_at: "2026-07-27T00:00:00.000Z",
        updated_at: "2026-07-27T00:00:00.000Z",
      }),
    );
  });
});

describe("parseAssignmentCandidate", () => {
  test("maps id/code/name only", () => {
    const candidate = parseAssignmentCandidate({ id: RESOURCE_ID, code: "VEND-1", name: "Contoso Trucking" });
    assert.deepEqual(candidate, { id: RESOURCE_ID, code: "VEND-1", name: "Contoso Trucking" });
  });
});

describe("AssignResourceInputSchema", () => {
  test("rejects an unsupported role", () => {
    assert.throws(() =>
      AssignResourceInputSchema.parse({
        shipmentOrderId: SHIPMENT_ID,
        role: "ship",
        resourceId: RESOURCE_ID,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });

  test("accepts a valid vendor assignment", () => {
    const parsed = AssignResourceInputSchema.parse({
      shipmentOrderId: SHIPMENT_ID,
      role: "vendor",
      resourceId: RESOURCE_ID,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(parsed.role, "vendor");
  });
});

describe("ReassignResourceInputSchema", () => {
  test("requires a non-empty reason", () => {
    assert.throws(() =>
      ReassignResourceInputSchema.parse({
        shipmentOrderId: SHIPMENT_ID,
        role: "vendor",
        newResourceId: RESOURCE_ID,
        reason: "",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });
});

describe("HoldResourceAssignmentInputSchema", () => {
  test("requires a non-empty reason", () => {
    assert.throws(() =>
      HoldResourceAssignmentInputSchema.parse({
        shipmentOrderId: SHIPMENT_ID,
        role: "vendor",
        reason: "",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });
});
