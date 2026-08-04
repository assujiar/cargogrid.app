import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  getWmsPackingTask,
  listWmsPackingTasks,
  getWmsPackage,
  listWmsPackageLines,
  listWmsPackageLineScans,
  listWmsPackageConfirmations,
  listWmsPackages,
  WmsPackingQueryError,
  type WmsPackingQueryClient,
} from "./wms-packing.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const WAREHOUSE_ID = "323e4567-e89b-12d3-a456-426614174000";
const OUTBOUND_ORDER_ID = "423e4567-e89b-12d3-a456-426614174000";
const PACKING_TASK_ID = "523e4567-e89b-12d3-a456-426614174000";
const PACKAGE_ID = "623e4567-e89b-12d3-a456-426614174000";
const OWNER_ID = "823e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "923e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: WmsPackingQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as WmsPackingQueryClient;
  return { client, calls };
}

const PACKING_TASK_ROW = {
  id: PACKING_TASK_ID,
  tenant_id: TENANT_ID,
  warehouse_id: WAREHOUSE_ID,
  outbound_order_id: OUTBOUND_ORDER_ID,
  owner_account_id: OWNER_ID,
  packing_task_number: "WMSPACK-2026-000001",
  idempotency_key: "idem-packtask-1",
  created_at: "2026-08-03T00:00:00.000Z",
};

const PACKAGE_ROW = {
  id: PACKAGE_ID,
  tenant_id: TENANT_ID,
  warehouse_id: WAREHOUSE_ID,
  packing_task_id: PACKING_TASK_ID,
  outbound_order_id: OUTBOUND_ORDER_ID,
  owner_account_id: OWNER_ID,
  parent_package_id: null,
  package_number: "PKG-2026-0000001",
  package_type: "carton",
  status: "open",
  weight_value: null,
  weight_uom_code: null,
  length_value: null,
  width_value: null,
  height_value: null,
  dimension_uom_code: null,
  material: null,
  qc_status: "pending",
  qc_reason: null,
  qc_by_auth_user_id: null,
  qc_by_label: null,
  qc_at: null,
  qc_override_reason: null,
  qc_override_by_auth_user_id: null,
  qc_override_by_label: null,
  qc_override_at: null,
  seal_number: null,
  sealed_by_auth_user_id: null,
  sealed_by_label: null,
  sealed_at: null,
  line_count: 0,
  total_packed_quantity: "0",
  confirmed_at: null,
  confirmed_by_auth_user_id: null,
  confirmed_by_label: null,
  reopen_count: 0,
  reopened_at: null,
  reopened_by_auth_user_id: null,
  reopened_by_label: null,
  reopened_reason: null,
  idempotency_key: "idem-pkg-1",
  record_version: 1,
  created_at: "2026-08-03T00:00:00.000Z",
  updated_at: "2026-08-03T00:00:00.000Z",
};

describe("getWmsPackingTask", () => {
  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [PACKING_TASK_ROW], error: null });
    const task = await getWmsPackingTask(client, PACKING_TASK_ID, ACTOR_ID);
    assert.equal(task.id, PACKING_TASK_ID);
    assert.equal(calls[0]?.fn, "get_wms_packing_task");
    assert.equal(calls[0]?.args.p_packing_task_id, PACKING_TASK_ID);
  });

  test("throws WmsPackingQueryError on an RPC error (e.g. cross-owner rejection)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity x is not owner-scoped to view packing task y" } });
    await assert.rejects(() => getWmsPackingTask(client, PACKING_TASK_ID, ACTOR_ID), WmsPackingQueryError);
  });
});

describe("listWmsPackingTasks", () => {
  test("defaults limit to 50 and passes optional filters through", async () => {
    const { client, calls } = fakeRpcClient({ data: [PACKING_TASK_ROW], error: null });
    const tasks = await listWmsPackingTasks(client, TENANT_ID, ACTOR_ID, { outboundOrderId: OUTBOUND_ORDER_ID });
    assert.equal(tasks.length, 1);
    assert.equal(calls[0]?.args.p_limit, 50);
    assert.equal(calls[0]?.args.p_outbound_order_id, OUTBOUND_ORDER_ID);
  });
});

describe("getWmsPackage", () => {
  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [PACKAGE_ROW], error: null });
    const pkg = await getWmsPackage(client, PACKAGE_ID, ACTOR_ID);
    assert.equal(pkg.id, PACKAGE_ID);
    assert.equal(calls[0]?.fn, "get_wms_package");
  });
});

describe("listWmsPackageLines", () => {
  test("returns an empty array when no rows are returned", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    const lines = await listWmsPackageLines(client, PACKAGE_ID, ACTOR_ID);
    assert.deepEqual(lines, []);
  });
});

describe("listWmsPackageLineScans", () => {
  test("sends the mapped RPC args", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listWmsPackageLineScans(client, PACKAGE_ID, ACTOR_ID);
    assert.equal(calls[0]?.fn, "list_wms_package_line_scans");
  });
});

describe("listWmsPackageConfirmations", () => {
  test("sends the mapped RPC args", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listWmsPackageConfirmations(client, PACKAGE_ID, ACTOR_ID);
    assert.equal(calls[0]?.fn, "list_wms_package_confirmations");
  });
});

describe("listWmsPackages", () => {
  test("bounded, record- and owner-scoped, optionally narrowed by status", async () => {
    const { client, calls } = fakeRpcClient({ data: [PACKAGE_ROW], error: null });
    const packages = await listWmsPackages(client, TENANT_ID, ACTOR_ID, { statusFilter: "open", limit: 25 });
    assert.equal(packages.length, 1);
    assert.equal(calls[0]?.args.p_status_filter, "open");
    assert.equal(calls[0]?.args.p_limit, 25);
  });
});
