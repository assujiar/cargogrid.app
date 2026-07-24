import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createCustomerContractDraft,
  addCustomerContractPriceComponent,
  publishCustomerContract,
  retireCustomerContract,
  ContractMutationError,
  type ContractMutationRpcClient,
} from "./contract.ts";

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

const COMPONENT_ROW = {
  id: "823e4567-e89b-12d3-a456-426614174000",
  tenant_id: TENANT_ID,
  contract_id: CONTRACT_ID,
  service_type: "ocean_freight",
  mode: "FCL",
  origin_lane: "Jakarta",
  destination_lane: "Surabaya",
  equipment_type: "20ft",
  currency: "IDR",
  base_amount: 12000000,
  minimum_amount: null,
  discount_pct: 5,
  surcharge_components: [],
  created_by: "tester",
  created_at: "2026-07-24T00:00:00.000Z",
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }, calls: { fn: string; args: Record<string, unknown> }[]): ContractMutationRpcClient {
  return {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as ContractMutationRpcClient;
}

describe("createCustomerContractDraft", () => {
  test("calls create_customer_contract_draft with exact snake_case params (main flow)", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: CONTRACT_ROW, error: null }, calls);
    const contract = await createCustomerContractDraft(client, { sourceQuotationId: QUOTATION_ID, effectiveFrom: "2026-08-01T00:00:00.000Z", actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.fn, "create_customer_contract_draft");
    assert.equal(calls[0]?.args.p_source_quotation_id, QUOTATION_ID);
    assert.equal(calls[0]?.args.p_source_contract_id, null);
    assert.equal(contract.status, "draft");
  });

  test("classifies quotation_not_converted", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "quotation_not_converted: quotation x has not been converted to an account yet" } }, []);
    await assert.rejects(
      () => createCustomerContractDraft(client, { sourceQuotationId: QUOTATION_ID, effectiveFrom: "2026-08-01T00:00:00.000Z", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof ContractMutationError);
        assert.equal(err.code, "quotation_not_converted");
        return true;
      },
    );
  });
});

describe("addCustomerContractPriceComponent", () => {
  test("calls add_customer_contract_price_component with exact snake_case params and marks the result unmasked", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: COMPONENT_ROW, error: null }, calls);
    const component = await addCustomerContractPriceComponent(client, {
      contractId: CONTRACT_ID,
      serviceType: "ocean_freight",
      currency: "IDR",
      baseAmount: 12000000,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(calls[0]?.fn, "add_customer_contract_price_component");
    assert.equal(calls[0]?.args.p_service_type, "ocean_freight");
    assert.equal(component.baseAmount, 12000000);
    assert.equal(component.priceMasked, false);
  });

  test("classifies invalid_currency", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "invalid_currency: idr is not a 3-letter ISO currency code" } }, []);
    await assert.rejects(
      () => addCustomerContractPriceComponent(client, { contractId: CONTRACT_ID, serviceType: "ocean_freight", currency: "IDR", baseAmount: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof ContractMutationError);
        assert.equal(err.code, "invalid_currency");
        return true;
      },
    );
  });
});

describe("publishCustomerContract", () => {
  test("classifies overlapping_active_version", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "overlapping_active_version: contract x overlaps already-published version y" } }, []);
    await assert.rejects(
      () => publishCustomerContract(client, { contractId: CONTRACT_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof ContractMutationError);
        assert.equal(err.code, "overlapping_active_version");
        return true;
      },
    );
  });

  test("classifies no_price_components", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "no_price_components: contract x has no price components to publish" } }, []);
    await assert.rejects(
      () => publishCustomerContract(client, { contractId: CONTRACT_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof ContractMutationError);
        assert.equal(err.code, "no_price_components");
        return true;
      },
    );
  });
});

describe("retireCustomerContract", () => {
  test("calls retire_customer_contract with the exact reason param", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: { ...CONTRACT_ROW, status: "retired", retired_reason: "Superseded" }, error: null }, calls);
    const contract = await retireCustomerContract(client, { contractId: CONTRACT_ID, expectedVersion: 1, reason: "Superseded", actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.args.p_reason, "Superseded");
    assert.equal(contract.status, "retired");
  });
});
