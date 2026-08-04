import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  getItemControlPolicy,
  listItemControlPolicyVersions,
  getLotIdentity,
  getSerialIdentity,
  listLotIdentities,
  listSerialIdentities,
  getLotTrace,
  getSerialTrace,
  listAllocationCandidates,
  LotBatchSerialQueryError,
  type LotBatchSerialQueryClient,
} from "./lot-batch-serial.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "723e4567-e89b-12d3-a456-426614174000";
const OWNER_ID = "823e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "923e4567-e89b-12d3-a456-426614174000";
const POLICY_ID = "a23e4567-e89b-12d3-a456-426614174000";
const LOT_ID = "b23e4567-e89b-12d3-a456-426614174000";
const SERIAL_ID = "c23e4567-e89b-12d3-a456-426614174000";
const WAREHOUSE_ID = "e23e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: LotBatchSerialQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as LotBatchSerialQueryClient;
  return { client, calls };
}

const POLICY_ROW = {
  id: POLICY_ID,
  tenant_id: TENANT_ID,
  item_master_id: ITEM_ID,
  owner_account_id: OWNER_ID,
  allocation_rule: "fifo",
  hold_on_unknown_lot: true,
  near_expiry_warning_days: null,
  status: "published",
  supersedes_version_id: null,
  effective_from: "2026-08-03T00:00:00.000Z",
  record_version: 1,
  created_at: "2026-08-03T00:00:00.000Z",
  updated_at: "2026-08-03T00:00:00.000Z",
};

const LOT_ROW = {
  id: LOT_ID,
  tenant_id: TENANT_ID,
  owner_account_id: OWNER_ID,
  item_master_id: ITEM_ID,
  lot_number: "LOT-001",
  manufacture_date: null,
  expiry_date: null,
  status: "active",
  hold_reason: null,
  parent_lot_id: null,
  source_type: "receipt",
  source_id: null,
  record_version: 1,
  created_at: "2026-08-03T00:00:00.000Z",
  updated_at: "2026-08-03T00:00:00.000Z",
};

const SERIAL_ROW = {
  id: SERIAL_ID,
  tenant_id: TENANT_ID,
  owner_account_id: OWNER_ID,
  item_master_id: ITEM_ID,
  serial_number: "SN-001",
  lot_number: null,
  manufacture_date: null,
  expiry_date: null,
  status: "active",
  hold_reason: null,
  source_type: "receipt",
  source_id: null,
  idempotency_key: "idem-serial-1",
  record_version: 1,
  created_at: "2026-08-03T00:00:00.000Z",
  updated_at: "2026-08-03T00:00:00.000Z",
};

describe("getItemControlPolicy", () => {
  test("maps the single returned row", async () => {
    const { client, calls } = fakeRpcClient({ data: [POLICY_ROW], error: null });
    const policy = await getItemControlPolicy(client, ITEM_ID, ACTOR_ID);
    assert.equal(policy.status, "published");
    assert.equal(calls[0]?.fn, "get_item_control_policy");
  });

  test("throws when no row is returned", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    await assert.rejects(() => getItemControlPolicy(client, ITEM_ID, ACTOR_ID), LotBatchSerialQueryError);
  });
});

describe("listItemControlPolicyVersions", () => {
  test("defaults every optional filter to null and limit to 50", async () => {
    const { client, calls } = fakeRpcClient({ data: [POLICY_ROW], error: null });
    const rows = await listItemControlPolicyVersions(client, TENANT_ID, ACTOR_ID);
    assert.equal(rows.length, 1);
    assert.equal(calls[0]?.args.p_item_master_id, null);
    assert.equal(calls[0]?.args.p_limit, 50);
  });
});

describe("getLotIdentity / getSerialIdentity", () => {
  test("getLotIdentity maps the single returned row", async () => {
    const { client, calls } = fakeRpcClient({ data: [LOT_ROW], error: null });
    const lot = await getLotIdentity(client, LOT_ID, ACTOR_ID);
    assert.equal(lot.lotNumber, "LOT-001");
    assert.equal(calls[0]?.fn, "get_lot_identity");
  });

  test("getSerialIdentity maps the single returned row", async () => {
    const { client, calls } = fakeRpcClient({ data: [SERIAL_ROW], error: null });
    const serial = await getSerialIdentity(client, SERIAL_ID, ACTOR_ID);
    assert.equal(serial.serialNumber, "SN-001");
    assert.equal(calls[0]?.fn, "get_serial_identity");
  });
});

describe("listLotIdentities / listSerialIdentities", () => {
  test("listLotIdentities passes through explicit filters", async () => {
    const { client, calls } = fakeRpcClient({ data: [LOT_ROW], error: null });
    await listLotIdentities(client, TENANT_ID, ACTOR_ID, { itemMasterId: ITEM_ID, statusFilter: "held", limit: 10 });
    assert.equal(calls[0]?.args.p_item_master_id, ITEM_ID);
    assert.equal(calls[0]?.args.p_status_filter, "held");
    assert.equal(calls[0]?.args.p_limit, 10);
  });

  test("listSerialIdentities returns an empty array when no data is returned", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    const rows = await listSerialIdentities(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(rows, []);
  });
});

describe("getLotTrace / getSerialTrace", () => {
  test("getLotTrace defaults limit to 50", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await getLotTrace(client, LOT_ID, ACTOR_ID);
    assert.equal(calls[0]?.args.p_limit, 50);
    assert.equal(calls[0]?.fn, "get_lot_trace");
  });

  test("getSerialTrace passes through an explicit limit", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await getSerialTrace(client, SERIAL_ID, ACTOR_ID, 5);
    assert.equal(calls[0]?.args.p_limit, 5);
    assert.equal(calls[0]?.fn, "get_serial_trace");
  });
});

describe("listAllocationCandidates", () => {
  test("defaults ownerAccountId/allocationRule to null and limit to 50", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listAllocationCandidates(client, TENANT_ID, WAREHOUSE_ID, ITEM_ID, ACTOR_ID);
    assert.equal(calls[0]?.args.p_owner_account_id, null);
    assert.equal(calls[0]?.args.p_allocation_rule, null);
    assert.equal(calls[0]?.args.p_limit, 50);
    assert.equal(calls[0]?.fn, "list_allocation_candidates");
  });

  test("passes through an explicit allocationRule override", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listAllocationCandidates(client, TENANT_ID, WAREHOUSE_ID, ITEM_ID, ACTOR_ID, { allocationRule: "fefo" });
    assert.equal(calls[0]?.args.p_allocation_rule, "fefo");
  });
});
