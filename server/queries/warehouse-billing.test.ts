import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  getWarehouseBillingEvent,
  listWarehouseBillingEvents,
  getWarehouseBillingHandoff,
  listWarehouseBillingHandoffs,
  listWarehouseBillingRateComponents,
  WarehouseBillingQueryError,
  type WarehouseBillingQueryClient,
} from "./warehouse-billing.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const CONTRACT_ID = "323e4567-e89b-12d3-a456-426614174000";
const WAREHOUSE_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const RATE_COMPONENT_ID = "723e4567-e89b-12d3-a456-426614174000";
const EVENT_ID = "823e4567-e89b-12d3-a456-426614174000";
const HANDOFF_ID = "923e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: WarehouseBillingQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as WarehouseBillingQueryClient;
  return { client, calls };
}

const EVENT_ROW = {
  id: EVENT_ID,
  tenant_id: TENANT_ID,
  warehouse_id: WAREHOUSE_ID,
  owner_account_id: ACCOUNT_ID,
  activity_type: "putaway",
  source_type: "wms_putaway_confirmation",
  source_id: "a23e4567-e89b-12d3-a456-426614174000",
  source_version: 1,
  activity_date: "2026-08-04T00:00:00.000Z",
  quantity: "10",
  uom_code: "PCS",
  contract_id: null,
  rate_component_id: null,
  base_amount: null,
  tax_code: null,
  tax_rule_version_id: null,
  tax_amount: null,
  total_amount: null,
  currency: null,
  rounding_mode: null,
  calculation_explanation: {},
  status: "draft",
  hold_reason: null,
  reviewed_by_auth_user_id: null,
  reviewed_by_label: null,
  reviewed_at: null,
  approved_by_auth_user_id: null,
  approved_by_label: null,
  approved_at: null,
  corrects_event_id: null,
  reverses_event_id: null,
  correction_reason: null,
  idempotency_key: "idem-1",
  record_version: 1,
  created_by: "rep",
  created_at: "2026-08-04T00:00:00.000Z",
  updated_at: "2026-08-04T00:00:00.000Z",
};

const HANDOFF_ROW = {
  id: HANDOFF_ID,
  tenant_id: TENANT_ID,
  billing_event_id: EVENT_ID,
  idempotency_key: "idem-handoff-1",
  handed_off_by_auth_user_id: ACTOR_ID,
  handed_off_by_label: "rep",
  handed_off_at: "2026-08-04T03:00:00.000Z",
  reconciliation_status: null,
  reconciliation_note: null,
  reconciled_at: null,
  updated_at: null,
  created_at: "2026-08-04T03:00:00.000Z",
};

const RATE_COMPONENT_ROW = {
  id: RATE_COMPONENT_ID,
  tenant_id: TENANT_ID,
  contract_id: CONTRACT_ID,
  warehouse_id: WAREHOUSE_ID,
  activity_type: "putaway",
  rate_basis: "per_unit",
  rate_uom_code: "PCS",
  unit_rate: "1500",
  minimum_amount: null,
  currency: "IDR",
  tier_schedule: null,
  time_basis_unit: null,
  record_version: 1,
  created_by: "rep",
  created_at: "2026-08-04T00:00:00.000Z",
  updated_at: "2026-08-04T00:00:00.000Z",
};

describe("getWarehouseBillingEvent", () => {
  test("calls the RPC with the right args and parses the row", async () => {
    const { client, calls } = fakeRpcClient({ data: [EVENT_ROW], error: null });
    const event = await getWarehouseBillingEvent(client, EVENT_ID, ACTOR_ID);
    assert.equal(calls[0]?.fn, "get_warehouse_billing_event");
    assert.deepEqual(calls[0]?.args, { p_event_id: EVENT_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(event.id, EVENT_ID);
  });

  test("throws WarehouseBillingQueryError on an RPC error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: nope" } });
    await assert.rejects(() => getWarehouseBillingEvent(client, EVENT_ID, ACTOR_ID), WarehouseBillingQueryError);
  });

  test("throws WarehouseBillingQueryError when no row is returned", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    await assert.rejects(() => getWarehouseBillingEvent(client, EVENT_ID, ACTOR_ID), WarehouseBillingQueryError);
  });
});

describe("listWarehouseBillingEvents", () => {
  test("defaults p_limit to 50 and every filter to null", async () => {
    const { client, calls } = fakeRpcClient({ data: [EVENT_ROW], error: null });
    await listWarehouseBillingEvents(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_warehouse_id: null,
      p_owner_account_id: null,
      p_activity_type: null,
      p_status_filter: null,
      p_limit: 50,
    });
  });

  test("passes through explicit filters and limit", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listWarehouseBillingEvents(client, TENANT_ID, ACTOR_ID, {
      warehouseId: WAREHOUSE_ID,
      ownerAccountId: ACCOUNT_ID,
      activityType: "outbound",
      statusFilter: "approved",
      limit: 200,
    });
    assert.equal(calls[0]?.args.p_warehouse_id, WAREHOUSE_ID);
    assert.equal(calls[0]?.args.p_status_filter, "approved");
    assert.equal(calls[0]?.args.p_limit, 200);
  });

  test("returns an empty array when data is null", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    const events = await listWarehouseBillingEvents(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(events, []);
  });
});

describe("getWarehouseBillingHandoff", () => {
  test("parses a handoff row", async () => {
    const { client } = fakeRpcClient({ data: [HANDOFF_ROW], error: null });
    const handoff = await getWarehouseBillingHandoff(client, HANDOFF_ID, ACTOR_ID);
    assert.equal(handoff.billingEventId, EVENT_ID);
  });
});

describe("listWarehouseBillingHandoffs", () => {
  test("defaults billingEventId filter to null", async () => {
    const { client, calls } = fakeRpcClient({ data: [HANDOFF_ROW], error: null });
    await listWarehouseBillingHandoffs(client, TENANT_ID, ACTOR_ID);
    assert.equal(calls[0]?.args.p_billing_event_id, null);
  });
});

describe("listWarehouseBillingRateComponents", () => {
  test("passes contractId and defaults", async () => {
    const { client, calls } = fakeRpcClient({ data: [RATE_COMPONENT_ROW], error: null });
    const rows = await listWarehouseBillingRateComponents(client, CONTRACT_ID, ACTOR_ID);
    assert.equal(calls[0]?.args.p_contract_id, CONTRACT_ID);
    assert.equal(calls[0]?.args.p_limit, 50);
    assert.equal(rows[0]?.id, RATE_COMPONENT_ID);
  });
});
