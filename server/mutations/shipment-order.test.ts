import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createShipmentOrderFromJob,
  confirmShipmentOrder,
  cancelShipmentOrder,
  ShipmentOrderMutationError,
  type ShipmentOrderMutationRpcClient,
} from "./shipment-order.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const JOB_ORDER_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: ShipmentOrderMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as ShipmentOrderMutationRpcClient;
  return { client, calls };
}

const BASE_ROW = {
  id: SHIPMENT_ID,
  tenant_id: TENANT_ID,
  job_order_id: JOB_ORDER_ID,
  shipment_number: "SHP-2026-000001",
  idempotency_key: "idem-1",
  status: "draft",
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
  record_version: 1,
  created_by: "rep",
  created_at: "2026-07-27T00:00:00.000Z",
  updated_at: "2026-07-27T00:00:00.000Z",
};

describe("createShipmentOrderFromJob", () => {
  test("calls create_shipment_order_from_job with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: BASE_ROW, error: null });
    const shipment = await createShipmentOrderFromJob(client, {
      jobOrderId: JOB_ORDER_ID,
      idempotencyKey: "idem-1",
      serviceType: "ocean_freight",
      mode: "sea",
      origin: "Jakarta",
      destination: "Surabaya",
      allocatedQuantity: 10,
      basisQuantity: 15,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });

    assert.equal(calls[0]?.fn, "create_shipment_order_from_job");
    assert.equal(calls[0]?.args.p_job_order_id, JOB_ORDER_ID);
    assert.equal(calls[0]?.args.p_idempotency_key, "idem-1");
    assert.equal(calls[0]?.args.p_mode, "sea");
    assert.equal(calls[0]?.args.p_allocated_quantity, 10);
    assert.equal(calls[0]?.args.p_basis_quantity, 15);
    assert.equal(calls[0]?.args.p_consignee, null);
    assert.equal(shipment.status, "draft");
  });

  test("classifies job_order_not_confirmed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "job_order_not_confirmed: job order is draft and is not eligible" } });
    await assert.rejects(
      () =>
        createShipmentOrderFromJob(client, {
          jobOrderId: JOB_ORDER_ID,
          idempotencyKey: "idem-1",
          serviceType: "ocean_freight",
          mode: "sea",
          origin: "Jakarta",
          destination: "Surabaya",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => {
        assert.ok(err instanceof ShipmentOrderMutationError);
        assert.equal(err.code, "job_order_not_confirmed");
        return true;
      },
    );
  });

  test("classifies split_reason_required", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "split_reason_required: a non-empty split_reason is required" } });
    await assert.rejects(
      () =>
        createShipmentOrderFromJob(client, {
          jobOrderId: JOB_ORDER_ID,
          idempotencyKey: "idem-2",
          serviceType: "ocean_freight",
          mode: "sea",
          origin: "Jakarta",
          destination: "Surabaya",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => {
        assert.ok(err instanceof ShipmentOrderMutationError);
        assert.equal(err.code, "split_reason_required");
        return true;
      },
    );
  });

  test("classifies over_allocation", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "over_allocation: allocated_quantity 11 exceeds remaining 5" } });
    await assert.rejects(
      () =>
        createShipmentOrderFromJob(client, {
          jobOrderId: JOB_ORDER_ID,
          idempotencyKey: "idem-3",
          serviceType: "ocean_freight",
          mode: "sea",
          origin: "Jakarta",
          destination: "Surabaya",
          allocatedQuantity: 11,
          splitReason: "partial cargo split",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => {
        assert.ok(err instanceof ShipmentOrderMutationError);
        assert.equal(err.code, "over_allocation");
        return true;
      },
    );
  });

  test("rejects an unsupported mode at the schema layer, before ever calling the RPC", async () => {
    const { client, calls } = fakeRpcClient({ data: BASE_ROW, error: null });
    await assert.rejects(() =>
      createShipmentOrderFromJob(client, {
        jobOrderId: JOB_ORDER_ID,
        idempotencyKey: "idem-1",
        serviceType: "ocean_freight",
        mode: "rail" as never,
        origin: "Jakarta",
        destination: "Surabaya",
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
        createShipmentOrderFromJob(client, {
          jobOrderId: JOB_ORDER_ID,
          idempotencyKey: "idem-1",
          serviceType: "ocean_freight",
          mode: "sea",
          origin: "Jakarta",
          destination: "Surabaya",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => {
        assert.ok(err instanceof ShipmentOrderMutationError);
        assert.equal(err.code, "mutation_failed");
        return true;
      },
    );
  });
});

describe("confirmShipmentOrder", () => {
  test("calls confirm_shipment_order with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...BASE_ROW, status: "confirmed", record_version: 2 }, error: null });
    const shipment = await confirmShipmentOrder(client, { shipmentOrderId: SHIPMENT_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });

    assert.deepEqual(calls[0]?.args, { p_shipment_order_id: SHIPMENT_ID, p_expected_version: 1, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "rep" });
    assert.equal(shipment.status, "confirmed");
  });

  test("classifies stale_version", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "stale_version: shipment order expected version 1 but found 2" } });
    await assert.rejects(
      () => confirmShipmentOrder(client, { shipmentOrderId: SHIPMENT_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof ShipmentOrderMutationError);
        assert.equal(err.code, "stale_version");
        return true;
      },
    );
  });
});

describe("cancelShipmentOrder", () => {
  test("calls cancel_shipment_order with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...BASE_ROW, status: "cancelled", record_version: 2 }, error: null });
    const shipment = await cancelShipmentOrder(client, { shipmentOrderId: SHIPMENT_ID, expectedVersion: 1, reason: "customer cancelled", actorAuthUserId: ACTOR_ID, actorLabel: "rep" });

    assert.deepEqual(calls[0]?.args, {
      p_shipment_order_id: SHIPMENT_ID,
      p_expected_version: 1,
      p_reason: "customer cancelled",
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "rep",
    });
    assert.equal(shipment.status, "cancelled");
  });

  test("rejects an empty reason before ever calling the RPC", async () => {
    const { client, calls } = fakeRpcClient({ data: BASE_ROW, error: null });
    await assert.rejects(() =>
      cancelShipmentOrder(client, { shipmentOrderId: SHIPMENT_ID, expectedVersion: 1, reason: "", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
    );
    assert.equal(calls.length, 0);
  });

  test("classifies cancel_reason_required", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "cancel_reason_required: a non-empty reason is required" } });
    await assert.rejects(
      () => cancelShipmentOrder(client, { shipmentOrderId: SHIPMENT_ID, expectedVersion: 1, reason: "x", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof ShipmentOrderMutationError);
        assert.equal(err.code, "cancel_reason_required");
        return true;
      },
    );
  });
});
