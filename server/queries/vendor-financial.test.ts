import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  getVendorBankAccountMasked,
  listVendorBankAccountsMasked,
  getVendorTaxIdentityMasked,
  listVendorTaxIdentitiesMasked,
  getVendorPaymentTermProposal,
  listVendorPaymentTermProposals,
  getVendorFinancialVerificationStatus,
  VendorFinancialQueryError,
  type VendorFinancialQueryClient,
} from "./vendor-financial.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VENDOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "123e4567-e89b-12d3-a456-426614174000";
const FAMILY_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const TAX_ID = "523e4567-e89b-12d3-a456-426614174000";
const PROPOSAL_ID = "823e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: VendorFinancialQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as VendorFinancialQueryClient;
  return { client, calls };
}

const BANK_ACCOUNT_ROW = {
  id: ACCOUNT_ID,
  tenant_id: TENANT_ID,
  vendor_master_record_id: VENDOR_ID,
  account_family_id: FAMILY_ID,
  account_holder_name: "PT Contoso Trucking",
  bank_name: "Bank Mandiri",
  account_number_last4: "0123",
  currency: "IDR",
  purpose: "primary",
  status: "active",
  effective_from: "2026-08-01",
  evidence_file_id: null,
  is_duplicate_candidate: false,
  proposed_by: "staff",
  approved_by: "approver",
  hold_reason: null,
  rejection_reason: null,
  deactivation_reason: null,
  record_version: 2,
  created_at: "2026-08-05T00:00:00.000Z",
  updated_at: "2026-08-05T00:00:00.000Z",
};

const TAX_IDENTITY_ROW = {
  id: TAX_ID,
  tenant_id: TENANT_ID,
  vendor_master_record_id: VENDOR_ID,
  tax_family_id: FAMILY_ID,
  tax_id_type: "NPWP",
  tax_id_last4: ".000",
  legal_name_on_file: "PT Contoso Trucking",
  status: "active",
  effective_from: "2026-08-01",
  evidence_file_id: null,
  is_duplicate_candidate: false,
  proposed_by: "staff",
  approved_by: "approver",
  hold_reason: null,
  rejection_reason: null,
  deactivation_reason: null,
  record_version: 1,
  created_at: "2026-08-05T00:00:00.000Z",
  updated_at: "2026-08-05T00:00:00.000Z",
};

describe("getVendorBankAccountMasked", () => {
  test("calls get_vendor_bank_account_masked and parses the row -- last4 only, never a secret field", async () => {
    const { client, calls } = fakeRpcClient({ data: [BANK_ACCOUNT_ROW], error: null });
    const result = await getVendorBankAccountMasked(client, ACCOUNT_ID, ACTOR_ID);
    assert.equal(calls[0]?.fn, "get_vendor_bank_account_masked");
    assert.equal(calls[0]?.args.p_account_id, ACCOUNT_ID);
    assert.equal(result.accountNumberLast4, "0123");
  });

  test("throws VendorFinancialQueryError when the RPC returns an error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "vendor_bank_account_not_found: x" } });
    await assert.rejects(() => getVendorBankAccountMasked(client, ACCOUNT_ID, ACTOR_ID), VendorFinancialQueryError);
  });

  test("throws VendorFinancialQueryError when the RPC returns no row", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    await assert.rejects(() => getVendorBankAccountMasked(client, ACCOUNT_ID, ACTOR_ID), VendorFinancialQueryError);
  });
});

describe("listVendorBankAccountsMasked", () => {
  test("defaults limit/afterId/statusFilter and forwards options when supplied", async () => {
    const { client, calls } = fakeRpcClient({ data: [BANK_ACCOUNT_ROW], error: null });
    const result = await listVendorBankAccountsMasked(client, VENDOR_ID, ACTOR_ID, { statusFilter: "active", limit: 10 });
    assert.equal(calls[0]?.args.p_status_filter, "active");
    assert.equal(calls[0]?.args.p_limit, 10);
    assert.equal(calls[0]?.args.p_after_id, null);
    assert.equal(result.length, 1);
  });
});

describe("getVendorTaxIdentityMasked", () => {
  test("calls get_vendor_tax_identity_masked and parses the row", async () => {
    const { client, calls } = fakeRpcClient({ data: [TAX_IDENTITY_ROW], error: null });
    const result = await getVendorTaxIdentityMasked(client, TAX_ID, ACTOR_ID);
    assert.equal(calls[0]?.fn, "get_vendor_tax_identity_masked");
    assert.equal(result.taxIdLast4, ".000");
  });
});

describe("listVendorTaxIdentitiesMasked", () => {
  test("calls list_vendor_tax_identities_masked with mapped args", async () => {
    const { client, calls } = fakeRpcClient({ data: [TAX_IDENTITY_ROW], error: null });
    await listVendorTaxIdentitiesMasked(client, VENDOR_ID, ACTOR_ID);
    assert.equal(calls[0]?.fn, "list_vendor_tax_identities_masked");
    assert.equal(calls[0]?.args.p_vendor_master_record_id, VENDOR_ID);
  });
});

describe("getVendorPaymentTermProposal / listVendorPaymentTermProposals", () => {
  const PROPOSAL_ROW = {
    id: PROPOSAL_ID,
    tenant_id: TENANT_ID,
    vendor_master_record_id: VENDOR_ID,
    current_payment_term_days: 30,
    proposed_payment_term_days: 45,
    vendor_profile_expected_version: 1,
    reason: "renegotiated",
    status: "pending_approval",
    proposed_by: "staff",
    approved_by: null,
    reauth_confirmed_at: null,
    decision_reason: null,
    record_version: 1,
    created_by: "staff",
    created_at: "2026-08-05T00:00:00.000Z",
    updated_at: "2026-08-05T00:00:00.000Z",
  };

  test("getVendorPaymentTermProposal parses the row", async () => {
    const { client } = fakeRpcClient({ data: [PROPOSAL_ROW], error: null });
    const result = await getVendorPaymentTermProposal(client, PROPOSAL_ID, ACTOR_ID);
    assert.equal(result.proposedPaymentTermDays, 45);
  });

  test("listVendorPaymentTermProposals forwards status filter", async () => {
    const { client, calls } = fakeRpcClient({ data: [PROPOSAL_ROW], error: null });
    await listVendorPaymentTermProposals(client, VENDOR_ID, ACTOR_ID, { statusFilter: "pending_approval" });
    assert.equal(calls[0]?.args.p_status_filter, "pending_approval");
  });
});

describe("getVendorFinancialVerificationStatus", () => {
  test("calls get_vendor_financial_verification_status and parses the downstream-composable row", async () => {
    const { client, calls } = fakeRpcClient({
      data: [{ vendor_master_record_id: VENDOR_ID, has_verified_bank_account: true, has_verified_tax_identity: true, on_hold: false, computed_at: "2026-08-05T00:00:00.000Z" }],
      error: null,
    });
    const result = await getVendorFinancialVerificationStatus(client, VENDOR_ID, ACTOR_ID);
    assert.equal(calls[0]?.fn, "get_vendor_financial_verification_status");
    assert.equal(result.hasVerifiedBankAccount, true);
    assert.equal(result.onHold, false);
  });
});
