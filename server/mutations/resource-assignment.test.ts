import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  assignResource,
  reassignResource,
  holdResourceAssignment,
  resumeResourceAssignment,
  unassignResource,
  ResourceAssignmentMutationError,
  type ResourceAssignmentMutationRpcClient,
} from "./resource-assignment.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ASSIGNMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const RESOURCE_ID = "623e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: ResourceAssignmentMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as ResourceAssignmentMutationRpcClient;
  return { client, calls };
}

const BASE_ROW = {
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
};

describe("assignResource", () => {
  test("calls assign_resource with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: BASE_ROW, error: null });
    const assignment = await assignResource(client, {
      shipmentOrderId: SHIPMENT_ID,
      role: "vendor",
      resourceId: RESOURCE_ID,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });

    assert.equal(calls[0]?.fn, "assign_resource");
    assert.deepEqual(calls[0]?.args, {
      p_shipment_order_id: SHIPMENT_ID,
      p_role: "vendor",
      p_resource_id: RESOURCE_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "rep",
    });
    assert.equal(assignment.status, "active");
  });

  test("classifies already_assigned", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "already_assigned: shipment order X already has a current vendor assignment -- use reassign_resource" } });
    await assert.rejects(
      () => assignResource(client, { shipmentOrderId: SHIPMENT_ID, role: "vendor", resourceId: RESOURCE_ID, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof ResourceAssignmentMutationError);
        assert.equal(err.code, "already_assigned");
        return true;
      },
    );
  });

  test("classifies assignment_conflict", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "assignment_conflict: resource X is already actively assigned on another shipment order" } });
    await assert.rejects(
      () => assignResource(client, { shipmentOrderId: SHIPMENT_ID, role: "vendor", resourceId: RESOURCE_ID, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof ResourceAssignmentMutationError);
        assert.equal(err.code, "assignment_conflict");
        return true;
      },
    );
  });

  test("classifies invalid_resource", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_resource: X is not an active vendor master record for tenant Y" } });
    await assert.rejects(
      () => assignResource(client, { shipmentOrderId: SHIPMENT_ID, role: "vendor", resourceId: RESOURCE_ID, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof ResourceAssignmentMutationError);
        assert.equal(err.code, "invalid_resource");
        return true;
      },
    );
  });

  test("falls back to mutation_failed for an unrecognized error message", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "boom, something unrelated broke" } });
    await assert.rejects(
      () => assignResource(client, { shipmentOrderId: SHIPMENT_ID, role: "vendor", resourceId: RESOURCE_ID, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof ResourceAssignmentMutationError);
        assert.equal(err.code, "mutation_failed");
        return true;
      },
    );
  });
});

describe("reassignResource", () => {
  test("calls reassign_resource with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...BASE_ROW, resource_snapshot: { code: "VEND-2", name: "Fabrikam Trucking" } }, error: null });
    const assignment = await reassignResource(client, {
      shipmentOrderId: SHIPMENT_ID,
      role: "vendor",
      newResourceId: RESOURCE_ID,
      reason: "underperforming",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });

    assert.equal(calls[0]?.fn, "reassign_resource");
    assert.deepEqual(calls[0]?.args, {
      p_shipment_order_id: SHIPMENT_ID,
      p_role: "vendor",
      p_new_resource_id: RESOURCE_ID,
      p_reason: "underperforming",
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "rep",
    });
    assert.equal(assignment.resourceSnapshot.code, "VEND-2");
  });

  test("rejects an empty reason at the schema layer, before ever calling the RPC", async () => {
    const { client, calls } = fakeRpcClient({ data: BASE_ROW, error: null });
    await assert.rejects(() =>
      reassignResource(client, { shipmentOrderId: SHIPMENT_ID, role: "vendor", newResourceId: RESOURCE_ID, reason: "", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
    );
    assert.equal(calls.length, 0);
  });

  test("classifies no_current_assignment", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "no_current_assignment: shipment order X has no current fleet assignment -- use assign_resource" } });
    await assert.rejects(
      () => reassignResource(client, { shipmentOrderId: SHIPMENT_ID, role: "fleet", newResourceId: RESOURCE_ID, reason: "swap", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof ResourceAssignmentMutationError);
        assert.equal(err.code, "no_current_assignment");
        return true;
      },
    );
  });
});

describe("holdResourceAssignment / resumeResourceAssignment", () => {
  test("holdResourceAssignment calls hold_resource_assignment with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...BASE_ROW, status: "held" }, error: null });
    const assignment = await holdResourceAssignment(client, { shipmentOrderId: SHIPMENT_ID, role: "vendor", reason: "vendor unresponsive", actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.fn, "hold_resource_assignment");
    assert.deepEqual(calls[0]?.args, {
      p_shipment_order_id: SHIPMENT_ID,
      p_role: "vendor",
      p_reason: "vendor unresponsive",
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "rep",
    });
    assert.equal(assignment.status, "held");
  });

  test("holdResourceAssignment rejects an empty reason at the schema layer", async () => {
    const { client, calls } = fakeRpcClient({ data: BASE_ROW, error: null });
    await assert.rejects(() => holdResourceAssignment(client, { shipmentOrderId: SHIPMENT_ID, role: "vendor", reason: "", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }));
    assert.equal(calls.length, 0);
  });

  test("resumeResourceAssignment calls resume_resource_assignment with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: BASE_ROW, error: null });
    const assignment = await resumeResourceAssignment(client, { shipmentOrderId: SHIPMENT_ID, role: "vendor", actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.fn, "resume_resource_assignment");
    assert.deepEqual(calls[0]?.args, {
      p_shipment_order_id: SHIPMENT_ID,
      p_role: "vendor",
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "rep",
    });
    assert.equal(assignment.status, "active");
  });

  test("classifies invalid_transition on either hold or resume", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_transition: current vendor assignment on shipment order X is held -- only an active assignment may be held" } });
    await assert.rejects(
      () => holdResourceAssignment(client, { shipmentOrderId: SHIPMENT_ID, role: "vendor", reason: "again", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof ResourceAssignmentMutationError);
        assert.equal(err.code, "invalid_transition");
        return true;
      },
    );
  });
});

describe("unassignResource", () => {
  test("calls unassign_resource with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...BASE_ROW, status: "unassigned", is_current: false }, error: null });
    const assignment = await unassignResource(client, { shipmentOrderId: SHIPMENT_ID, role: "fleet", reason: "no longer needed", actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.fn, "unassign_resource");
    assert.deepEqual(calls[0]?.args, {
      p_shipment_order_id: SHIPMENT_ID,
      p_role: "fleet",
      p_reason: "no longer needed",
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "rep",
    });
    assert.equal(assignment.status, "unassigned");
    assert.equal(assignment.isCurrent, false);
  });

  test("rejects an empty reason at the schema layer, before ever calling the RPC", async () => {
    const { client, calls } = fakeRpcClient({ data: BASE_ROW, error: null });
    await assert.rejects(() => unassignResource(client, { shipmentOrderId: SHIPMENT_ID, role: "fleet", reason: "", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }));
    assert.equal(calls.length, 0);
  });
});
