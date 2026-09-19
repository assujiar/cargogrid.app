import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listCustomerContracts, getCustomerContractById, getCustomerContractForQuotation, listCustomerContractPriceComponents, getEffectiveCustomerPrice, ContractQueryError, type ContractQueryClient } from "./contract.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "323e4567-e89b-12d3-a456-426614174000";
const CONTRACT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const QUOTATION_ID = "723e4567-e89b-12d3-a456-426614174000";

const CONTRACT_ROW = {
  id: CONTRACT_ID,
  tenant_id: TENANT_ID,
  account_id: ACCOUNT_ID,
  root_contract_id: CONTRACT_ID,
  version_number: 1,
  status: "draft",
  source_quotation_id: QUOTATION_ID,
  amendment_reason: null,
  effective_from: "2026-08-01T00:00:00.000Z",
  effective_to: null,
  retired_reason: null,
  owner_user_id: ACTOR_ID,
  org_unit_id: null,
  record_version: 1,
  created_by: "tester",
  created_at: "2026-07-24T00:00:00.000Z",
  updated_at: "2026-07-24T00:00:00.000Z",
};

function fakeClient(opts: { rpcResponse?: { data: unknown; error: { message: string } | null } }): ContractQueryClient & {
  calls: { rpc: { fn: string; args: Record<string, unknown> }[] };
} {
  const calls = {
    rpc: [] as { fn: string; args: Record<string, unknown> }[],
  };
  const fake = {
    calls,
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.rpc.push({ fn, args });
      return opts.rpcResponse ?? { data: [], error: null };
    },
  };
  return fake as unknown as ContractQueryClient & { calls: typeof calls };
}

describe("listCustomerContracts", () => {
  test("calls list_customer_contracts with tenant/actor/limit, newest first", async () => {
    const client = fakeClient({ rpcResponse: { data: [CONTRACT_ROW], error: null } });
    const contracts = await listCustomerContracts(client, TENANT_ID, ACTOR_ID);
    assert.equal(client.calls.rpc[0]?.fn, "list_customer_contracts");
    assert.deepEqual(client.calls.rpc[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_limit: 200 });
    assert.equal(contracts.rows[0]?.status, "draft");
    assert.equal(contracts.truncated, false);
  });

  test("reports truncated when the row count reaches the cap", async () => {
    const client = fakeClient({ rpcResponse: { data: Array.from({ length: 200 }, () => CONTRACT_ROW), error: null } });
    const contracts = await listCustomerContracts(client, TENANT_ID, ACTOR_ID);
    assert.equal(contracts.truncated, true);
  });
});

describe("getCustomerContractById", () => {
  test("returns null when not found", async () => {
    const client = fakeClient({ rpcResponse: { data: [], error: null } });
    const contract = await getCustomerContractById(client, CONTRACT_ID, ACTOR_ID);
    assert.equal(contract, null);
  });

  test("wraps a query error", async () => {
    const client = fakeClient({ rpcResponse: { data: null, error: { message: "boom" } } });
    await assert.rejects(
      () => getCustomerContractById(client, CONTRACT_ID, ACTOR_ID),
      (err: unknown) => {
        assert.ok(err instanceof ContractQueryError);
        return true;
      },
    );
  });
});

describe("getCustomerContractForQuotation", () => {
  test("returns null when no contract exists", async () => {
    const client = fakeClient({ rpcResponse: { data: [], error: null } });
    const contract = await getCustomerContractForQuotation(client, QUOTATION_ID, ACTOR_ID);
    assert.equal(contract, null);
  });

  test("maps an existing contract row", async () => {
    const client = fakeClient({ rpcResponse: { data: [CONTRACT_ROW], error: null } });
    const contract = await getCustomerContractForQuotation(client, QUOTATION_ID, ACTOR_ID);
    assert.equal(contract?.id, CONTRACT_ID);
  });
});

describe("listCustomerContractPriceComponents", () => {
  test("calls list_customer_contract_price_components with contract/actor", async () => {
    const client = fakeClient({ rpcResponse: { data: [], error: null } });
    await listCustomerContractPriceComponents(client, CONTRACT_ID, ACTOR_ID);
    assert.equal(client.calls.rpc[0]?.fn, "list_customer_contract_price_components");
    assert.deepEqual(client.calls.rpc[0]?.args, { p_contract_id: CONTRACT_ID, p_actor_auth_user_id: ACTOR_ID });
  });
});

describe("getEffectiveCustomerPrice", () => {
  test("resolves asOf to the current time in JS when null, not relying on the RPC's own default", async () => {
    const client = fakeClient({
      rpcResponse: {
        data: [{ contract_id: CONTRACT_ID, price_component_id: CONTRACT_ID, service_type: "ocean_freight", mode: null, origin_lane: null, destination_lane: null, equipment_type: null, currency: "IDR", base_amount: 1, minimum_amount: null, discount_pct: 0, surcharge_components: [], price_masked: false, effective_from: "2026-08-01T00:00:00.000Z", effective_to: null }],
        error: null,
      },
    });
    await getEffectiveCustomerPrice(client, { tenantId: TENANT_ID, accountId: ACCOUNT_ID, serviceType: "ocean_freight", actorAuthUserId: ACTOR_ID });
    assert.equal(client.calls.rpc[0]?.fn, "get_effective_customer_price");
    assert.equal(typeof client.calls.rpc[0]?.args.p_as_of, "string");
  });

  test("wraps a no_effective_price RPC error", async () => {
    const client = fakeClient({ rpcResponse: { data: null, error: { message: "no_effective_price: no match" } } });
    await assert.rejects(() => getEffectiveCustomerPrice(client, { tenantId: TENANT_ID, accountId: ACCOUNT_ID, serviceType: "ocean_freight", actorAuthUserId: ACTOR_ID }));
  });
});
