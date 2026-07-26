import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseCustomerContract,
  parseCustomerContractPriceComponent,
  parseEffectiveCustomerPrice,
  CreateCustomerContractDraftInputSchema,
  AddCustomerContractPriceComponentInputSchema,
  GetEffectiveCustomerPriceInputSchema,
} from "./contract.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "323e4567-e89b-12d3-a456-426614174000";
const CONTRACT_ID = "423e4567-e89b-12d3-a456-426614174000";
const COMPONENT_ID = "523e4567-e89b-12d3-a456-426614174000";
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
  id: COMPONENT_ID,
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
  price_masked: false,
  created_by: "tester",
  created_at: "2026-07-24T00:00:00.000Z",
};

describe("parseCustomerContract", () => {
  test("maps a full row", () => {
    const contract = parseCustomerContract(CONTRACT_ROW);
    assert.equal(contract.status, "draft");
    assert.equal(contract.versionNumber, 1);
    assert.equal(contract.rootContractId, CONTRACT_ID);
    assert.equal(contract.sourceQuotationId, QUOTATION_ID);
  });
});

describe("parseCustomerContractPriceComponent", () => {
  test("maps an unmasked row", () => {
    const component = parseCustomerContractPriceComponent(COMPONENT_ROW);
    assert.equal(component.priceMasked, false);
    assert.equal(component.baseAmount, 12000000);
  });

  test("maps a masked row with null money fields", () => {
    const component = parseCustomerContractPriceComponent({ ...COMPONENT_ROW, currency: null, base_amount: null, minimum_amount: null, discount_pct: null, surcharge_components: null, price_masked: true });
    assert.equal(component.priceMasked, true);
    assert.equal(component.baseAmount, null);
  });
});

describe("parseEffectiveCustomerPrice", () => {
  test("maps an unmasked lookup result", () => {
    const result = parseEffectiveCustomerPrice({
      contract_id: CONTRACT_ID,
      price_component_id: COMPONENT_ID,
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
      price_masked: false,
      effective_from: "2026-08-01T00:00:00.000Z",
      effective_to: null,
    });
    assert.equal(result.baseAmount, 12000000);
    assert.equal(result.priceMasked, false);
  });
});

describe("CreateCustomerContractDraftInputSchema", () => {
  test("accepts sourceQuotationId alone (main flow)", () => {
    const parsed = CreateCustomerContractDraftInputSchema.parse({
      sourceQuotationId: QUOTATION_ID,
      effectiveFrom: "2026-08-01T00:00:00.000Z",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(parsed.sourceQuotationId, QUOTATION_ID);
    assert.equal(parsed.sourceContractId, null);
  });

  test("accepts sourceContractId alone (renewal flow)", () => {
    const parsed = CreateCustomerContractDraftInputSchema.parse({
      sourceContractId: CONTRACT_ID,
      effectiveFrom: "2026-08-01T00:00:00.000Z",
      amendmentReason: "Annual renewal",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(parsed.sourceContractId, CONTRACT_ID);
    assert.equal(parsed.sourceQuotationId, null);
  });

  test("rejects both sourceQuotationId and sourceContractId set", () => {
    assert.throws(() =>
      CreateCustomerContractDraftInputSchema.parse({
        sourceQuotationId: QUOTATION_ID,
        sourceContractId: CONTRACT_ID,
        effectiveFrom: "2026-08-01T00:00:00.000Z",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });

  test("rejects neither sourceQuotationId nor sourceContractId set", () => {
    assert.throws(() =>
      CreateCustomerContractDraftInputSchema.parse({
        effectiveFrom: "2026-08-01T00:00:00.000Z",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });
});

describe("AddCustomerContractPriceComponentInputSchema", () => {
  test("defaults discountPct to 0 and surchargeComponents to []", () => {
    const parsed = AddCustomerContractPriceComponentInputSchema.parse({
      contractId: CONTRACT_ID,
      serviceType: "ocean_freight",
      currency: "IDR",
      baseAmount: 12000000,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(parsed.discountPct, 0);
    assert.deepEqual(parsed.surchargeComponents, []);
  });

  test("rejects a malformed currency code", () => {
    assert.throws(() =>
      AddCustomerContractPriceComponentInputSchema.parse({
        contractId: CONTRACT_ID,
        serviceType: "ocean_freight",
        currency: "idr",
        baseAmount: 12000000,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });

  test("rejects a negative baseAmount", () => {
    assert.throws(() =>
      AddCustomerContractPriceComponentInputSchema.parse({
        contractId: CONTRACT_ID,
        serviceType: "ocean_freight",
        currency: "IDR",
        baseAmount: -1,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });
});

describe("GetEffectiveCustomerPriceInputSchema", () => {
  test("defaults optional dimensions and asOf to null", () => {
    const parsed = GetEffectiveCustomerPriceInputSchema.parse({
      tenantId: TENANT_ID,
      accountId: ACCOUNT_ID,
      serviceType: "ocean_freight",
      actorAuthUserId: ACTOR_ID,
    });
    assert.equal(parsed.mode, null);
    assert.equal(parsed.asOf, null);
  });
});
