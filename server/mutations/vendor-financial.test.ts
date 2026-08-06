import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createVendorBankAccountDraft,
  decideVendorBankAccountApproval,
  holdVendorBankAccount,
  revealVendorBankAccountNumber,
  accessVendorBankAccountEvidence,
  createVendorTaxIdentityDraft,
  decideVendorTaxIdentityApproval,
  revealVendorTaxIdentityNumber,
  proposeVendorPaymentTermChange,
  decideVendorPaymentTermChangeProposal,
  VendorFinancialMutationError,
  type VendorFinancialMutationRpcClient,
} from "./vendor-financial.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VENDOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "123e4567-e89b-12d3-a456-426614174000";
const FAMILY_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const TAX_ID = "523e4567-e89b-12d3-a456-426614174000";
const FILE_ID = "723e4567-e89b-12d3-a456-426614174000";
const PROPOSAL_ID = "823e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: VendorFinancialMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as VendorFinancialMutationRpcClient;
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
  status: "draft",
  effective_from: null,
  evidence_file_id: null,
  proposed_by: "staff",
  approved_by: null,
  hold_reason: null,
  rejection_reason: null,
  deactivation_reason: null,
  record_version: 1,
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
  status: "draft",
  effective_from: null,
  evidence_file_id: null,
  proposed_by: "staff",
  approved_by: null,
  hold_reason: null,
  rejection_reason: null,
  deactivation_reason: null,
  record_version: 1,
  created_at: "2026-08-05T00:00:00.000Z",
  updated_at: "2026-08-05T00:00:00.000Z",
};

describe("createVendorBankAccountDraft", () => {
  test("calls create_vendor_bank_account_draft with mapped snake_case args, forwarding the plaintext number ONLY as p_account_number", async () => {
    const { client, calls } = fakeRpcClient({ data: [BANK_ACCOUNT_ROW], error: null });
    const result = await createVendorBankAccountDraft(client, {
      vendorMasterRecordId: VENDOR_ID,
      accountHolderName: "PT Contoso Trucking",
      bankName: "Bank Mandiri",
      bankAccountNumber: "1234567890123",
      currency: "IDR",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "staff",
    });
    assert.equal(calls[0]?.fn, "create_vendor_bank_account_draft");
    assert.equal(calls[0]?.args.p_account_number, "1234567890123");
    assert.equal(result.status, "draft");
  });

  test("classifies a known error code from the rpc error message", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_currency: ZZZ is not a registered, active currency" } });
    await assert.rejects(
      () =>
        createVendorBankAccountDraft(client, {
          vendorMasterRecordId: VENDOR_ID,
          accountHolderName: "x",
          bankName: "x",
          bankAccountNumber: "1234567890123",
          currency: "ZZZ",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "staff",
        }),
      (error: unknown) => {
        assert.ok(error instanceof VendorFinancialMutationError);
        assert.equal(error.code, "invalid_currency");
        return true;
      },
    );
  });

  test("classifies encryption_key_not_configured (fail-closed design note 1)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "encryption_key_not_configured: app.vendor_financial_encryption_key is not set" } });
    await assert.rejects(
      () =>
        createVendorBankAccountDraft(client, {
          vendorMasterRecordId: VENDOR_ID,
          accountHolderName: "x",
          bankName: "x",
          bankAccountNumber: "1234567890123",
          currency: "IDR",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "staff",
        }),
      (error: unknown) => {
        assert.ok(error instanceof VendorFinancialMutationError);
        assert.equal(error.code, "encryption_key_not_configured");
        return true;
      },
    );
  });

  test("falls back to mutation_failed for an unrecognized error prefix", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "some_unmapped_db_error: oops" } });
    await assert.rejects(
      () =>
        createVendorBankAccountDraft(client, {
          vendorMasterRecordId: VENDOR_ID,
          accountHolderName: "x",
          bankName: "x",
          bankAccountNumber: "1234567890123",
          currency: "IDR",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "staff",
        }),
      (error: unknown) => {
        assert.ok(error instanceof VendorFinancialMutationError);
        assert.equal(error.code, "mutation_failed");
        return true;
      },
    );
  });
});

describe("decideVendorBankAccountApproval", () => {
  test("forwards reauthConfirmedAt and supersedesAccountId", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...BANK_ACCOUNT_ROW, status: "active" }], error: null });
    const reauth = new Date().toISOString();
    const result = await decideVendorBankAccountApproval(client, {
      accountId: ACCOUNT_ID,
      expectedVersion: 1,
      decision: "approved",
      supersedesAccountId: FAMILY_ID,
      reauthConfirmedAt: reauth,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "approver",
    });
    assert.equal(calls[0]?.args.p_reauth_confirmed_at, reauth);
    assert.equal(calls[0]?.args.p_supersedes_account_id, FAMILY_ID);
    assert.equal(result.status, "active");
  });

  test("classifies self_approval_not_allowed (mandatory maker-checker, design note 7)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "self_approval_not_allowed: identity X proposed bank account Y and may not also decide it" } });
    await assert.rejects(
      () =>
        decideVendorBankAccountApproval(client, {
          accountId: ACCOUNT_ID,
          expectedVersion: 1,
          decision: "approved",
          reauthConfirmedAt: new Date().toISOString(),
          actorAuthUserId: ACTOR_ID,
          actorLabel: "staff",
        }),
      (error: unknown) => {
        assert.ok(error instanceof VendorFinancialMutationError);
        assert.equal(error.code, "self_approval_not_allowed");
        return true;
      },
    );
  });

  test("classifies reauth_required (MFA freshness, design notes 6-7)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "reauth_required: re-authentication must have completed within the last 5 minutes" } });
    await assert.rejects(
      () =>
        decideVendorBankAccountApproval(client, {
          accountId: ACCOUNT_ID,
          expectedVersion: 1,
          decision: "approved",
          reauthConfirmedAt: new Date(Date.now() - 10 * 60 * 1000).toISOString(),
          actorAuthUserId: ACTOR_ID,
          actorLabel: "approver",
        }),
      (error: unknown) => {
        assert.ok(error instanceof VendorFinancialMutationError);
        assert.equal(error.code, "reauth_required");
        return true;
      },
    );
  });
});

describe("holdVendorBankAccount", () => {
  test("requires a non-empty reason at the schema layer before any RPC call", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...BANK_ACCOUNT_ROW, status: "hold" }], error: null });
    await assert.rejects(() =>
      holdVendorBankAccount(client, { accountId: ACCOUNT_ID, expectedVersion: 1, reason: "", reauthConfirmedAt: new Date().toISOString(), actorAuthUserId: ACTOR_ID, actorLabel: "manager" }),
    );
    assert.equal(calls.length, 0);
  });
});

describe("revealVendorBankAccountNumber", () => {
  test("maps the RPC's decrypted response into bankAccountNumber, never a bare accountNumber", async () => {
    const { client, calls } = fakeRpcClient({
      data: [{ account_number: "1234567890123", account_holder_name: "PT Contoso Trucking", bank_name: "Bank Mandiri", currency: "IDR", purpose: "primary", status: "active" }],
      error: null,
    });
    const result = await revealVendorBankAccountNumber(client, {
      accountId: ACCOUNT_ID,
      revealReason: "invoice matching",
      reauthConfirmedAt: new Date().toISOString(),
      actorAuthUserId: ACTOR_ID,
      actorLabel: "pdv",
    });
    assert.equal(calls[0]?.fn, "reveal_vendor_bank_account_number");
    assert.equal(calls[0]?.args.p_reveal_reason, "invoice matching");
    assert.equal(result.bankAccountNumber, "1234567890123");
  });

  test("classifies reveal_reason_required", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "reveal_reason_required: a non-empty, purpose-bound reason is required" } });
    await assert.rejects(
      () =>
        revealVendorBankAccountNumber(client, {
          accountId: ACCOUNT_ID,
          revealReason: "x",
          reauthConfirmedAt: new Date().toISOString(),
          actorAuthUserId: ACTOR_ID,
          actorLabel: "pdv",
        }),
      (error: unknown) => {
        assert.ok(error instanceof VendorFinancialMutationError);
        assert.equal(error.code, "reveal_reason_required");
        return true;
      },
    );
  });
});

describe("accessVendorBankAccountEvidence", () => {
  test("calls access_vendor_bank_account_evidence and parses a granted result", async () => {
    const { client, calls } = fakeRpcClient({
      data: [
        {
          file_id: FILE_ID,
          original_filename: "bank-letter.pdf",
          mime_type: "application/pdf",
          size_bytes: 1024,
          malware_scan_status: "clean",
          classification: "confidential",
          legal_hold: false,
          uploaded_at: "2026-08-05T00:00:00.000Z",
          access_result: "granted",
          access_reason: null,
        },
      ],
      error: null,
    });
    const result = await accessVendorBankAccountEvidence(client, { accountId: ACCOUNT_ID, accessType: "metadata_view", actorAuthUserId: ACTOR_ID, actorLabel: "staff" });
    assert.equal(calls[0]?.fn, "access_vendor_bank_account_evidence");
    assert.equal(result.accessResult, "granted");
    assert.equal(result.originalFilename, "bank-letter.pdf");
  });
});

describe("createVendorTaxIdentityDraft / decideVendorTaxIdentityApproval / revealVendorTaxIdentityNumber", () => {
  test("createVendorTaxIdentityDraft maps taxIdNumber to p_tax_id", async () => {
    const { client, calls } = fakeRpcClient({ data: [TAX_IDENTITY_ROW], error: null });
    await createVendorTaxIdentityDraft(client, {
      vendorMasterRecordId: VENDOR_ID,
      taxIdType: "NPWP",
      taxIdNumber: "01.234.567.8-901.000",
      legalNameOnFile: "PT Contoso Trucking",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "staff",
    });
    assert.equal(calls[0]?.args.p_tax_id, "01.234.567.8-901.000");
  });

  test("decideVendorTaxIdentityApproval classifies self_approval_not_allowed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "self_approval_not_allowed: identity X proposed tax identity Y" } });
    await assert.rejects(
      () =>
        decideVendorTaxIdentityApproval(client, {
          taxIdentityId: TAX_ID,
          expectedVersion: 1,
          decision: "approved",
          reauthConfirmedAt: new Date().toISOString(),
          actorAuthUserId: ACTOR_ID,
          actorLabel: "staff",
        }),
      (error: unknown) => {
        assert.ok(error instanceof VendorFinancialMutationError);
        assert.equal(error.code, "self_approval_not_allowed");
        return true;
      },
    );
  });

  test("revealVendorTaxIdentityNumber maps the decrypted response into taxIdNumber", async () => {
    const { client } = fakeRpcClient({
      data: [{ tax_id: "01.234.567.8-901.000", tax_id_type: "NPWP", legal_name_on_file: "PT Contoso Trucking", status: "active" }],
      error: null,
    });
    const result = await revealVendorTaxIdentityNumber(client, {
      taxIdentityId: TAX_ID,
      revealReason: "annual tax audit",
      reauthConfirmedAt: new Date().toISOString(),
      actorAuthUserId: ACTOR_ID,
      actorLabel: "pdv",
    });
    assert.equal(result.taxIdNumber, "01.234.567.8-901.000");
  });
});

describe("proposeVendorPaymentTermChange / decideVendorPaymentTermChangeProposal", () => {
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

  test("proposeVendorPaymentTermChange maps args", async () => {
    const { client, calls } = fakeRpcClient({ data: [PROPOSAL_ROW], error: null });
    const result = await proposeVendorPaymentTermChange(client, { vendorMasterRecordId: VENDOR_ID, proposedPaymentTermDays: 45, reason: "renegotiated", actorAuthUserId: ACTOR_ID, actorLabel: "staff" });
    assert.equal(calls[0]?.fn, "propose_vendor_payment_term_change");
    assert.equal(calls[0]?.args.p_proposed_payment_term_days, 45);
    assert.equal(result.status, "pending_approval");
  });

  test("decideVendorPaymentTermChangeProposal classifies vendor_profile_changed_since_proposal", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "vendor_profile_changed_since_proposal: vendor X profile changed since this proposal was made" } });
    await assert.rejects(
      () =>
        decideVendorPaymentTermChangeProposal(client, {
          proposalId: PROPOSAL_ID,
          expectedVersion: 1,
          decision: "approved",
          reauthConfirmedAt: new Date().toISOString(),
          actorAuthUserId: ACTOR_ID,
          actorLabel: "approver",
        }),
      (error: unknown) => {
        assert.ok(error instanceof VendorFinancialMutationError);
        assert.equal(error.code, "vendor_profile_changed_since_proposal");
        return true;
      },
    );
  });
});
