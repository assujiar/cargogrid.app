import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createWmsOutboundShipment,
  addPackageToShipment,
  removePackageFromShipment,
  setWmsShipmentVehicleRef,
  setWmsShipmentDockLocation,
  loadWmsOutboundShipment,
  shipConfirmWmsOutboundShipment,
  cancelWmsOutboundShipment,
  WmsOutboundMutationError,
  type WmsOutboundMutationRpcClient,
} from "./wms-outbound.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const WAREHOUSE_ID = "323e4567-e89b-12d3-a456-426614174000";
const OUTBOUND_ORDER_ID = "423e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "523e4567-e89b-12d3-a456-426614174000";
const OWNER_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";
const DOCK_LOCATION_ID = "823e4567-e89b-12d3-a456-426614174000";
const PACKAGE_ID = "923e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: WmsOutboundMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as WmsOutboundMutationRpcClient;
  return { client, calls };
}

const SHIPMENT_ROW = {
  id: SHIPMENT_ID,
  tenant_id: TENANT_ID,
  warehouse_id: WAREHOUSE_ID,
  outbound_order_id: OUTBOUND_ORDER_ID,
  owner_account_id: OWNER_ID,
  shipment_number: "WMSSHIP-2026-000001",
  idempotency_key: "idem-ship-1",
  status: "staging",
  dock_location_id: null,
  vehicle_ref: null,
  loaded_at: null,
  loaded_by_auth_user_id: null,
  loaded_by_label: null,
  load_movement_id: null,
  custody_confirmed_by_label: null,
  custody_confirmed_reason: null,
  custody_confirmed_at: null,
  shipped_at: null,
  shipped_by_auth_user_id: null,
  shipped_by_label: null,
  consumption_movement_id: null,
  is_partial_fulfillment: false,
  partial_fulfillment_reason: null,
  cancelled_at: null,
  cancelled_by_auth_user_id: null,
  cancelled_by_label: null,
  cancelled_reason: null,
  record_version: 1,
  created_at: "2026-08-04T00:00:00.000Z",
  updated_at: "2026-08-04T00:00:00.000Z",
};

describe("createWmsOutboundShipment", () => {
  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [SHIPMENT_ROW], error: null });
    const shipment = await createWmsOutboundShipment(client, { outboundOrderId: OUTBOUND_ORDER_ID, idempotencyKey: "idem-ship-1", actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(shipment.outboundOrderId, OUTBOUND_ORDER_ID);
    assert.equal(calls[0]?.fn, "create_wms_outbound_shipment");
  });

  test("classifies outbound_order_not_confirmed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "outbound_order_not_confirmed: x is draft -- only confirmed outbound demand may be shipped against" } });
    await assert.rejects(
      () => createWmsOutboundShipment(client, { outboundOrderId: OUTBOUND_ORDER_ID, idempotencyKey: "idem-ship-2", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => err instanceof WmsOutboundMutationError && err.code === "outbound_order_not_confirmed",
    );
  });

  test("classifies an unrecognized error prefix as mutation_failed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "some_unexpected_db_error: boom" } });
    await assert.rejects(
      () => createWmsOutboundShipment(client, { outboundOrderId: OUTBOUND_ORDER_ID, idempotencyKey: "idem-ship-3", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => err instanceof WmsOutboundMutationError && err.code === "mutation_failed",
    );
  });
});

describe("addPackageToShipment", () => {
  test("sends the mapped RPC args", async () => {
    const { client, calls } = fakeRpcClient({ data: [SHIPMENT_ROW], error: null });
    await addPackageToShipment(client, { shipmentId: SHIPMENT_ID, packageId: PACKAGE_ID, idempotencyKey: "idem-add-1", actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.fn, "add_package_to_shipment");
    assert.equal(calls[0]?.args.p_package_id, PACKAGE_ID);
  });

  test("classifies wrong_order", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "wrong_order: package x belongs to outbound order y, not this shipment's own outbound order z" } });
    await assert.rejects(
      () => addPackageToShipment(client, { shipmentId: SHIPMENT_ID, packageId: PACKAGE_ID, idempotencyKey: "idem-add-2", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => err instanceof WmsOutboundMutationError && err.code === "wrong_order",
    );
  });

  test("classifies package_already_staged", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "package_already_staged: package x is already staged for a different shipment" } });
    await assert.rejects(
      () => addPackageToShipment(client, { shipmentId: SHIPMENT_ID, packageId: PACKAGE_ID, idempotencyKey: "idem-add-3", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => err instanceof WmsOutboundMutationError && err.code === "package_already_staged",
    );
  });
});

describe("removePackageFromShipment", () => {
  test("returns a boolean, never re-parsing a shipment row", async () => {
    const { client, calls } = fakeRpcClient({ data: true, error: null });
    const result = await removePackageFromShipment(client, { shipmentId: SHIPMENT_ID, packageId: PACKAGE_ID, reason: "wrong package staged", actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(result, true);
    assert.equal(calls[0]?.fn, "remove_package_from_shipment");
  });
});

describe("setWmsShipmentVehicleRef", () => {
  test("sends the mapped RPC args and allows a null vehicleRef", async () => {
    const { client, calls } = fakeRpcClient({ data: [SHIPMENT_ROW], error: null });
    await setWmsShipmentVehicleRef(client, { shipmentId: SHIPMENT_ID, vehicleRef: null, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.args.p_vehicle_ref, null);
  });

  test("classifies shipment_locked", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "shipment_locked: x is shipped -- the vehicle reference may only change before ship-confirm" } });
    await assert.rejects(
      () => setWmsShipmentVehicleRef(client, { shipmentId: SHIPMENT_ID, vehicleRef: "TRUCK-002", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => err instanceof WmsOutboundMutationError && err.code === "shipment_locked",
    );
  });
});

describe("setWmsShipmentDockLocation", () => {
  test("sends the mapped RPC args", async () => {
    const { client, calls } = fakeRpcClient({ data: [SHIPMENT_ROW], error: null });
    await setWmsShipmentDockLocation(client, { shipmentId: SHIPMENT_ID, dockLocationId: DOCK_LOCATION_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.args.p_dock_location_id, DOCK_LOCATION_ID);
  });

  test("classifies incompatible_location", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "incompatible_location: x is a rack -- a real dock location is required" } });
    await assert.rejects(
      () => setWmsShipmentDockLocation(client, { shipmentId: SHIPMENT_ID, dockLocationId: DOCK_LOCATION_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => err instanceof WmsOutboundMutationError && err.code === "incompatible_location",
    );
  });
});

describe("loadWmsOutboundShipment", () => {
  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...SHIPMENT_ROW, status: "loaded" }], error: null });
    const shipment = await loadWmsOutboundShipment(client, { shipmentId: SHIPMENT_ID, idempotencyKey: "idem-load-1", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(shipment.status, "loaded");
    assert.equal(calls[0]?.fn, "load_wms_outbound_shipment");
  });

  test("classifies dock_location_not_set", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "dock_location_not_set: set a dock location before loading" } });
    await assert.rejects(
      () => loadWmsOutboundShipment(client, { shipmentId: SHIPMENT_ID, idempotencyKey: "idem-load-2", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => err instanceof WmsOutboundMutationError && err.code === "dock_location_not_set",
    );
  });

  test("classifies empty_shipment_rejected", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "empty_shipment_rejected: shipment x has no staged packages" } });
    await assert.rejects(
      () => loadWmsOutboundShipment(client, { shipmentId: SHIPMENT_ID, idempotencyKey: "idem-load-3", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => err instanceof WmsOutboundMutationError && err.code === "empty_shipment_rejected",
    );
  });
});

describe("shipConfirmWmsOutboundShipment", () => {
  test("sends the mapped RPC args, including custody/partial-fulfillment fields, and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...SHIPMENT_ROW, status: "shipped" }], error: null });
    const shipment = await shipConfirmWmsOutboundShipment(client, {
      shipmentId: SHIPMENT_ID,
      custodyConfirmedByLabel: "Driver Joko",
      custodyConfirmedReason: "handoff to carrier",
      isPartialFulfillment: false,
      partialFulfillmentReason: null,
      idempotencyKey: "idem-confirm-1",
      expectedVersion: 1,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(shipment.status, "shipped");
    assert.equal(calls[0]?.fn, "ship_confirm_wms_outbound_shipment");
    assert.equal(calls[0]?.args.p_custody_confirmed_by_label, "Driver Joko");
    assert.equal(calls[0]?.args.p_is_partial_fulfillment, false);
  });

  test("classifies custody_required", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "custody_required: a real custody-confirming actor label is required" } });
    await assert.rejects(
      () =>
        shipConfirmWmsOutboundShipment(client, {
          shipmentId: SHIPMENT_ID,
          custodyConfirmedByLabel: "Driver Joko",
          custodyConfirmedReason: "handoff to carrier",
          isPartialFulfillment: false,
          partialFulfillmentReason: null,
          idempotencyKey: "idem-confirm-2",
          expectedVersion: 1,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => err instanceof WmsOutboundMutationError && err.code === "custody_required",
    );
  });

  test("classifies partial_fulfillment_not_acknowledged", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "partial_fulfillment_not_acknowledged: 1 of 2 confirmed packages remain unshipped" } });
    await assert.rejects(
      () =>
        shipConfirmWmsOutboundShipment(client, {
          shipmentId: SHIPMENT_ID,
          custodyConfirmedByLabel: "Driver Joko",
          custodyConfirmedReason: "handoff to carrier",
          isPartialFulfillment: false,
          partialFulfillmentReason: null,
          idempotencyKey: "idem-confirm-3",
          expectedVersion: 1,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => err instanceof WmsOutboundMutationError && err.code === "partial_fulfillment_not_acknowledged",
    );
  });

  test("classifies invalid_transition on a genuine double-confirm attempt", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_transition: x must be loaded to ship-confirm, is shipped" } });
    await assert.rejects(
      () =>
        shipConfirmWmsOutboundShipment(client, {
          shipmentId: SHIPMENT_ID,
          custodyConfirmedByLabel: "Driver Joko",
          custodyConfirmedReason: "second attempt",
          isPartialFulfillment: false,
          partialFulfillmentReason: null,
          idempotencyKey: "idem-confirm-4",
          expectedVersion: 1,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => err instanceof WmsOutboundMutationError && err.code === "invalid_transition",
    );
  });
});

describe("cancelWmsOutboundShipment", () => {
  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...SHIPMENT_ROW, status: "cancelled" }], error: null });
    const shipment = await cancelWmsOutboundShipment(client, { shipmentId: SHIPMENT_ID, reason: "wrong order staged", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(shipment.status, "cancelled");
    assert.equal(calls[0]?.fn, "cancel_wms_outbound_shipment");
  });

  test("classifies shipment_not_cancellable", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "shipment_not_cancellable: x is loaded -- only an uncommitted (staging) shipment may be cancelled here" } });
    await assert.rejects(
      () => cancelWmsOutboundShipment(client, { shipmentId: SHIPMENT_ID, reason: "test", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => err instanceof WmsOutboundMutationError && err.code === "shipment_not_cancellable",
    );
  });
});
