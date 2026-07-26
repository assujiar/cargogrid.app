import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseAccount,
  parseAccountConversionReadiness,
  FindDuplicateAccountsInputSchema,
  GetAccountConversionReadinessInputSchema,
  ConvertQuotationToAccountInputSchema,
} from "./account.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "323e4567-e89b-12d3-a456-426614174000";
const PROSPECT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const QUOTATION_ID = "623e4567-e89b-12d3-a456-426614174000";

const ACCOUNT_ROW = {
  id: ACCOUNT_ID,
  tenant_id: TENANT_ID,
  legal_name: "Contoso Ltd",
  trade_name: "Contoso",
  tax_id: "01.234.567.8-901.000",
  billing_address: { city: "Jakarta" },
  customer_status: "active",
  parent_account_id: null,
  source_prospect_id: PROSPECT_ID,
  status: "active",
  merged_into_id: null,
  merged_at: null,
  owner_user_id: ACTOR_ID,
  org_unit_id: null,
  record_version: 1,
  created_by: "tester",
  created_at: "2026-07-24T00:00:00.000Z",
  updated_at: "2026-07-24T00:00:00.000Z",
};

describe("parseAccount", () => {
  test("maps a full row, including billing address and customer status", () => {
    const account = parseAccount(ACCOUNT_ROW);
    assert.equal(account.legalName, "Contoso Ltd");
    assert.deepEqual(account.billingAddress, { city: "Jakarta" });
    assert.equal(account.customerStatus, "active");
    assert.equal(account.parentAccountId, null);
  });

  test("defaults a missing billing_address to an empty object", () => {
    const { billing_address: _omit, ...rowWithoutBillingAddress } = ACCOUNT_ROW;
    const account = parseAccount(rowWithoutBillingAddress);
    assert.deepEqual(account.billingAddress, {});
  });
});

describe("parseAccountConversionReadiness", () => {
  test("maps ready=true with a duplicate candidate", () => {
    const readiness = parseAccountConversionReadiness({ ready: true, blocking_reasons: [], duplicate_candidate_ids: [ACCOUNT_ID] });
    assert.equal(readiness.ready, true);
    assert.deepEqual(readiness.duplicateCandidateIds, [ACCOUNT_ID]);
  });

  test("maps ready=false with blocking reasons and no candidates", () => {
    const readiness = parseAccountConversionReadiness({ ready: false, blocking_reasons: ["quotation_not_accepted"], duplicate_candidate_ids: [] });
    assert.equal(readiness.ready, false);
    assert.deepEqual(readiness.blockingReasons, ["quotation_not_accepted"]);
  });
});

describe("FindDuplicateAccountsInputSchema", () => {
  test("defaults taxId to null", () => {
    const parsed = FindDuplicateAccountsInputSchema.parse({ tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, legalName: "Contoso Ltd" });
    assert.equal(parsed.taxId, null);
  });

  test("rejects an empty legalName", () => {
    assert.throws(() => FindDuplicateAccountsInputSchema.parse({ tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, legalName: "" }));
  });
});

describe("GetAccountConversionReadinessInputSchema", () => {
  test("parses a valid input", () => {
    const parsed = GetAccountConversionReadinessInputSchema.parse({ quotationId: QUOTATION_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(parsed.quotationId, QUOTATION_ID);
  });
});

describe("ConvertQuotationToAccountInputSchema", () => {
  test("defaults targetAccountId and parentAccountId to null", () => {
    const parsed = ConvertQuotationToAccountInputSchema.parse({ quotationId: QUOTATION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(parsed.targetAccountId, null);
    assert.equal(parsed.parentAccountId, null);
  });

  test("accepts an explicit targetAccountId (the link-to-existing flow)", () => {
    const parsed = ConvertQuotationToAccountInputSchema.parse({ quotationId: QUOTATION_ID, targetAccountId: ACCOUNT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(parsed.targetAccountId, ACCOUNT_ID);
  });
});
