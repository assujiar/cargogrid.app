import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseVendorBankAccount,
  parseVendorBankAccountReveal,
  parseVendorTaxIdentity,
  parseVendorTaxIdentityReveal,
  parseVendorPaymentTermProposal,
  parseVendorFinancialVerificationStatus,
  parseVendorFinancialEvidenceAccess,
  CreateVendorBankAccountDraftInputSchema,
  DecideVendorBankAccountApprovalInputSchema,
  RevealVendorBankAccountNumberInputSchema,
  CreateVendorTaxIdentityDraftInputSchema,
  ProposeVendorPaymentTermChangeInputSchema,
} from "./vendor-financial.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VENDOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "123e4567-e89b-12d3-a456-426614174000";
const FAMILY_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const TAX_ID = "523e4567-e89b-12d3-a456-426614174000";
const FILE_ID = "723e4567-e89b-12d3-a456-426614174000";

describe("parseVendorBankAccount", () => {
  test("maps snake_case row fields -- NEVER touches an encrypted/hash field (the row shape structurally cannot carry one)", () => {
    const result = parseVendorBankAccount({
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
      evidence_file_id: FILE_ID,
      is_duplicate_candidate: false,
      proposed_by: "staff",
      approved_by: "approver",
      hold_reason: null,
      rejection_reason: null,
      deactivation_reason: null,
      record_version: 2,
      created_at: "2026-08-05T00:00:00.000Z",
      updated_at: "2026-08-05T00:00:00.000Z",
    });
    assert.equal(result.accountNumberLast4, "0123");
    assert.equal(result.isDuplicateCandidate, false);
    assert.equal(result.status, "active");
    // Structural guarantee: this parsed shape has no field named/derived from the
    // encrypted or hash columns at all -- verified by key enumeration, not just by
    // omission from this one fixture.
    assert.ok(!Object.keys(result).some((k) => /encrypted|hash/i.test(k)));
  });

  test("is_duplicate_candidate coerces truthy/falsy", () => {
    const base = {
      id: ACCOUNT_ID,
      tenant_id: TENANT_ID,
      vendor_master_record_id: VENDOR_ID,
      account_family_id: FAMILY_ID,
      account_holder_name: "x",
      bank_name: "x",
      account_number_last4: "0000",
      currency: "IDR",
      purpose: "primary",
      status: "draft",
      effective_from: null,
      evidence_file_id: null,
      proposed_by: null,
      approved_by: null,
      hold_reason: null,
      rejection_reason: null,
      deactivation_reason: null,
      record_version: 1,
      created_at: "2026-08-05T00:00:00.000Z",
      updated_at: "2026-08-05T00:00:00.000Z",
    };
    assert.equal(parseVendorBankAccount({ ...base, is_duplicate_candidate: true }).isDuplicateCandidate, true);
    assert.equal(parseVendorBankAccount({ ...base, is_duplicate_candidate: false }).isDuplicateCandidate, false);
  });
});

describe("parseVendorBankAccountReveal", () => {
  test("maps the decrypted account_number column into bankAccountNumber (never a bare accountNumber -- see this contract file's own logger-redaction naming note)", () => {
    const result = parseVendorBankAccountReveal({
      account_number: "1234567890123",
      account_holder_name: "PT Contoso Trucking",
      bank_name: "Bank Mandiri",
      currency: "IDR",
      purpose: "primary",
      status: "active",
    });
    assert.equal(result.bankAccountNumber, "1234567890123");
    assert.ok(!("accountNumber" in result));
  });
});

describe("parseVendorTaxIdentity", () => {
  test("maps snake_case row fields", () => {
    const result = parseVendorTaxIdentity({
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
      is_duplicate_candidate: true,
      proposed_by: "staff",
      approved_by: "approver",
      hold_reason: null,
      rejection_reason: null,
      deactivation_reason: null,
      record_version: 3,
      created_at: "2026-08-05T00:00:00.000Z",
      updated_at: "2026-08-05T00:00:00.000Z",
    });
    assert.equal(result.taxIdType, "NPWP");
    assert.equal(result.taxIdLast4, ".000");
    assert.equal(result.isDuplicateCandidate, true);
  });
});

describe("parseVendorTaxIdentityReveal", () => {
  test("maps the decrypted tax_id column into taxIdNumber", () => {
    const result = parseVendorTaxIdentityReveal({
      tax_id: "01.234.567.8-901.000",
      tax_id_type: "NPWP",
      legal_name_on_file: "PT Contoso Trucking",
      status: "active",
    });
    assert.equal(result.taxIdNumber, "01.234.567.8-901.000");
  });
});

describe("parseVendorPaymentTermProposal", () => {
  test("maps snake_case row fields, nulls through nullable columns", () => {
    const result = parseVendorPaymentTermProposal({
      id: ACCOUNT_ID,
      tenant_id: TENANT_ID,
      vendor_master_record_id: VENDOR_ID,
      current_payment_term_days: 30,
      proposed_payment_term_days: 45,
      vendor_profile_expected_version: 1,
      reason: "renegotiated terms",
      status: "pending_approval",
      proposed_by: "staff",
      approved_by: null,
      reauth_confirmed_at: null,
      decision_reason: null,
      record_version: 1,
      created_by: "staff",
      created_at: "2026-08-05T00:00:00.000Z",
      updated_at: "2026-08-05T00:00:00.000Z",
    });
    assert.equal(result.currentPaymentTermDays, 30);
    assert.equal(result.proposedPaymentTermDays, 45);
    assert.equal(result.approvedBy, null);
  });
});

describe("parseVendorFinancialVerificationStatus", () => {
  test("maps and coerces booleans -- the sole downstream-composable read shape", () => {
    const result = parseVendorFinancialVerificationStatus({
      vendor_master_record_id: VENDOR_ID,
      has_verified_bank_account: true,
      has_verified_tax_identity: false,
      on_hold: false,
      computed_at: "2026-08-05T00:00:00.000Z",
    });
    assert.equal(result.hasVerifiedBankAccount, true);
    assert.equal(result.hasVerifiedTaxIdentity, false);
    assert.equal(result.onHold, false);
  });
});

describe("parseVendorFinancialEvidenceAccess", () => {
  test("a denied result nulls out file-identifying fields, matching the RPC's own contract", () => {
    const result = parseVendorFinancialEvidenceAccess({
      file_id: FILE_ID,
      original_filename: null,
      mime_type: null,
      size_bytes: null,
      malware_scan_status: null,
      classification: null,
      legal_hold: null,
      uploaded_at: null,
      access_result: "denied",
      access_reason: "malware_scan_not_clean",
    });
    assert.equal(result.accessResult, "denied");
    assert.equal(result.originalFilename, null);
  });

  test("an authority-denied result nulls out fileId itself (security-rls fix -- a caller lacking PRC:Download must not learn whether evidence is attached)", () => {
    const result = parseVendorFinancialEvidenceAccess({
      file_id: null,
      original_filename: null,
      mime_type: null,
      size_bytes: null,
      malware_scan_status: null,
      classification: null,
      legal_hold: null,
      uploaded_at: null,
      access_result: "denied",
      access_reason: "insufficient_authority: actor lacks PRC:Download",
    });
    assert.equal(result.accessResult, "denied");
    assert.equal(result.fileId, null);
  });
});

describe("CreateVendorBankAccountDraftInputSchema", () => {
  test("rejects a bank account number shorter than 4 characters", () => {
    assert.throws(() =>
      CreateVendorBankAccountDraftInputSchema.parse({
        vendorMasterRecordId: VENDOR_ID,
        accountHolderName: "x",
        bankName: "x",
        bankAccountNumber: "12",
        currency: "IDR",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "staff",
      }),
    );
  });

  test("accepts a valid payload with optional fields omitted", () => {
    const parsed = CreateVendorBankAccountDraftInputSchema.parse({
      vendorMasterRecordId: VENDOR_ID,
      accountHolderName: "PT Contoso Trucking",
      bankName: "Bank Mandiri",
      bankAccountNumber: "1234567890123",
      currency: "IDR",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "staff",
    });
    assert.equal(parsed.purpose, undefined);
  });
});

describe("DecideVendorBankAccountApprovalInputSchema", () => {
  test("requires reauthConfirmedAt (MFA freshness, design notes 6-7)", () => {
    assert.throws(() =>
      DecideVendorBankAccountApprovalInputSchema.parse({
        accountId: ACCOUNT_ID,
        expectedVersion: 1,
        decision: "approved",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "approver",
      }),
    );
  });
});

describe("RevealVendorBankAccountNumberInputSchema", () => {
  test("requires a non-empty revealReason (purpose-bound reveal, Sec.16)", () => {
    assert.throws(() =>
      RevealVendorBankAccountNumberInputSchema.parse({
        accountId: ACCOUNT_ID,
        revealReason: "",
        reauthConfirmedAt: new Date().toISOString(),
        actorAuthUserId: ACTOR_ID,
        actorLabel: "pdv",
      }),
    );
  });
});

describe("CreateVendorTaxIdentityDraftInputSchema", () => {
  test("rejects a tax id shorter than 4 characters", () => {
    assert.throws(() =>
      CreateVendorTaxIdentityDraftInputSchema.parse({
        vendorMasterRecordId: VENDOR_ID,
        taxIdType: "NPWP",
        taxIdNumber: "12",
        legalNameOnFile: "x",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "staff",
      }),
    );
  });
});

describe("ProposeVendorPaymentTermChangeInputSchema", () => {
  test("rejects a negative proposedPaymentTermDays", () => {
    assert.throws(() =>
      ProposeVendorPaymentTermChangeInputSchema.parse({
        vendorMasterRecordId: VENDOR_ID,
        proposedPaymentTermDays: -1,
        reason: "x",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "staff",
      }),
    );
  });

  test("rejects an empty reason", () => {
    assert.throws(() =>
      ProposeVendorPaymentTermChangeInputSchema.parse({
        vendorMasterRecordId: VENDOR_ID,
        proposedPaymentTermDays: 45,
        reason: "",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "staff",
      }),
    );
  });
});
