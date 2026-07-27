import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { transitionShipmentOrder, ShipmentLifecycleMutationError, type ShipmentLifecycleMutationRpcClient } from "./shipment-lifecycle.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const JOB_ORDER_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: ShipmentLifecycleMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as ShipmentLifecycleMutationRpcClient;
  return { client, calls };
}

const BASE_ROW = {
  id: SHIPMENT_ID,
  tenant_id: TENANT_ID,
  job_order_id: JOB_ORDER_ID,
  shipment_number: "SHP-2026-000001",
  idempotency_key: "idem-1",
  status: "planned",
  shipper_account_id: ACCOUNT_ID,
  consignee_snapshot: { legal_name: "Acme Shipping Co" },
  notify_party_snapshot: null,
  cargo_service_snapshot: { service_type: "ocean_freight" },
  service_type: "ocean_freight",
  mode: "sea",
  origin: "Jakarta",
  destination: "Surabaya",
  planned_pickup_at: null,
  planned_delivery_at: null,
  basis_quantity: 15,
  basis_weight_kg: 1500,
  basis_volume_cbm: 30,
  allocated_quantity: 10,
  allocated_weight_kg: 1000,
  allocated_volume_cbm: 20,
  split_reason: null,
  owner_user_id: ACTOR_ID,
  org_unit_id: null,
  record_version: 2,
  created_by: "rep",
  created_at: "2026-07-27T00:00:00.000Z",
  updated_at: "2026-07-27T00:00:00.000Z",
};

describe("transitionShipmentOrder", () => {
  test("calls transition_shipment_order with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: BASE_ROW, error: null });
    const shipment = await transitionShipmentOrder(client, {
      shipmentOrderId: SHIPMENT_ID,
      toStatus: "planned",
      expectedVersion: 1,
      idempotencyKey: "idem-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });

    assert.equal(calls[0]?.fn, "transition_shipment_order");
    assert.deepEqual(calls[0]?.args, {
      p_shipment_order_id: SHIPMENT_ID,
      p_to_status: "planned",
      p_expected_version: 1,
      p_reason: null,
      p_evidence_ref: null,
      p_idempotency_key: "idem-1",
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "rep",
    });
    assert.equal(shipment.status, "planned");
  });

  test("classifies reason_required", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "reason_required: a non-empty reason is required to enter held" } });
    await assert.rejects(
      () =>
        transitionShipmentOrder(client, {
          shipmentOrderId: SHIPMENT_ID,
          toStatus: "held",
          expectedVersion: 1,
          idempotencyKey: "idem-2",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => {
        assert.ok(err instanceof ShipmentLifecycleMutationError);
        assert.equal(err.code, "reason_required");
        return true;
      },
    );
  });

  test("classifies evidence_required", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "evidence_required: a non-empty evidence reference is required to enter delivered" } });
    await assert.rejects(
      () =>
        transitionShipmentOrder(client, {
          shipmentOrderId: SHIPMENT_ID,
          toStatus: "delivered",
          expectedVersion: 1,
          idempotencyKey: "idem-3",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => {
        assert.ok(err instanceof ShipmentLifecycleMutationError);
        assert.equal(err.code, "evidence_required");
        return true;
      },
    );
  });

  test("classifies invalid_transition", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_transition: confirmed -> delivered is not a legal Shipment Order transition" } });
    await assert.rejects(
      () =>
        transitionShipmentOrder(client, {
          shipmentOrderId: SHIPMENT_ID,
          toStatus: "delivered",
          expectedVersion: 1,
          evidenceRef: "POD-0001",
          idempotencyKey: "idem-4",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => {
        assert.ok(err instanceof ShipmentLifecycleMutationError);
        assert.equal(err.code, "invalid_transition");
        return true;
      },
    );
  });

  test("classifies insufficient_authority (a non-Supreme reopen attempt)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: reopening a closed shipment order requires Supreme Admin authority (RPD-022)" } });
    await assert.rejects(
      () =>
        transitionShipmentOrder(client, {
          shipmentOrderId: SHIPMENT_ID,
          toStatus: "delivered",
          expectedVersion: 5,
          evidenceRef: "POD-0001",
          idempotencyKey: "idem-5",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => {
        assert.ok(err instanceof ShipmentLifecycleMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });

  test("rejects an unsupported toStatus at the schema layer, before ever calling the RPC", async () => {
    const { client, calls } = fakeRpcClient({ data: BASE_ROW, error: null });
    await assert.rejects(() =>
      transitionShipmentOrder(client, {
        shipmentOrderId: SHIPMENT_ID,
        toStatus: "draft" as never,
        expectedVersion: 1,
        idempotencyKey: "idem-1",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
    assert.equal(calls.length, 0);
  });

  test("falls back to mutation_failed for an unrecognized error message", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "boom, something unrelated broke" } });
    await assert.rejects(
      () =>
        transitionShipmentOrder(client, {
          shipmentOrderId: SHIPMENT_ID,
          toStatus: "planned",
          expectedVersion: 1,
          idempotencyKey: "idem-6",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => {
        assert.ok(err instanceof ShipmentLifecycleMutationError);
        assert.equal(err.code, "mutation_failed");
        return true;
      },
    );
  });
});
