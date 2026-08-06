import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseVendorComplianceRequirement,
  parseVendorComplianceDocument,
  parseVendorComplianceWaiver,
  parseVendorComplianceStatusRow,
  parseVendorComplianceEligibilityRow,
  parseVendorComplianceMatrixRow,
  CreateVendorComplianceRequirementDraftInputSchema,
  SubmitVendorComplianceDocumentInputSchema,
  RequestVendorComplianceWaiverInputSchema,
} from "./vendor-compliance.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VENDOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const REQ_ID = "123e4567-e89b-12d3-a456-426614174000";
const FAMILY_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const DOC_ID = "523e4567-e89b-12d3-a456-426614174000";
const FILE_ID = "723e4567-e89b-12d3-a456-426614174000";
const WAIVER_ID = "823e4567-e89b-12d3-a456-426614174000";

describe("parseVendorComplianceRequirement", () => {
  test("maps snake_case row fields, including reminder_offsets array coercion", () => {
    const result = parseVendorComplianceRequirement({
      id: REQ_ID,
      tenant_id: TENANT_ID,
      requirement_family_id: FAMILY_ID,
      vendor_category: "trucking",
      service_type: null,
      document_type_code: "vendor_compliance_document",
      name: "Business License",
      description: null,
      blocking_effect: "blocking",
      requires_expiry: true,
      reminder_offsets: [30, 14, 7],
      status: "published",
      supersedes_version_id: null,
      effective_from: "2026-08-05T00:00:00.000Z",
      record_version: 1,
      created_by: "staff",
      created_at: "2026-08-05T00:00:00.000Z",
      updated_at: "2026-08-05T00:00:00.000Z",
    });
    assert.equal(result.requirementFamilyId, FAMILY_ID);
    assert.deepEqual(result.reminderOffsets, [30, 14, 7]);
    assert.equal(result.blockingEffect, "blocking");
  });

  test("defaults reminder_offsets to an empty array when the row omits it entirely", () => {
    const result = parseVendorComplianceRequirement({
      id: REQ_ID,
      tenant_id: TENANT_ID,
      requirement_family_id: FAMILY_ID,
      vendor_category: null,
      service_type: null,
      document_type_code: "vendor_compliance_document",
      name: "Business License",
      description: null,
      blocking_effect: "warning",
      requires_expiry: false,
      status: "draft",
      supersedes_version_id: null,
      effective_from: "2026-08-05T00:00:00.000Z",
      record_version: 1,
      created_by: null,
      created_at: "2026-08-05T00:00:00.000Z",
      updated_at: "2026-08-05T00:00:00.000Z",
    });
    assert.deepEqual(result.reminderOffsets, []);
  });
});

describe("parseVendorComplianceDocument", () => {
  test("maps snake_case row fields and coerces booleans", () => {
    const result = parseVendorComplianceDocument({
      id: DOC_ID,
      tenant_id: TENANT_ID,
      vendor_master_record_id: VENDOR_ID,
      requirement_version_id: REQ_ID,
      file_id: FILE_ID,
      version_group_id: DOC_ID,
      version_number: 1,
      is_latest_version: true,
      issue_date: "2026-01-01",
      expiry_date: "2027-01-01",
      verification_status: "verified",
      verified_by: "approver",
      verified_by_auth_user_id: ACTOR_ID,
      verified_at: "2026-08-05T00:00:00.000Z",
      rejection_reason: null,
      record_version: 2,
      created_by: "staff",
      created_at: "2026-08-05T00:00:00.000Z",
      updated_at: "2026-08-05T00:00:00.000Z",
    });
    assert.equal(result.isLatestVersion, true);
    assert.equal(result.verificationStatus, "verified");
    assert.equal(result.expiryDate, "2027-01-01");
  });
});

describe("parseVendorComplianceWaiver", () => {
  test("maps snake_case row fields", () => {
    const result = parseVendorComplianceWaiver({
      id: WAIVER_ID,
      tenant_id: TENANT_ID,
      requirement_version_id: REQ_ID,
      vendor_master_record_id: VENDOR_ID,
      reason: "operational exception",
      valid_from: "2026-08-01",
      valid_until: "2026-08-31",
      requested_by: "staff",
      requested_by_auth_user_id: ACTOR_ID,
      approved_by: null,
      approved_by_auth_user_id: null,
      decision_reason: null,
      status: "pending",
      record_version: 1,
      created_by: "staff",
      created_at: "2026-08-05T00:00:00.000Z",
      updated_at: "2026-08-05T00:00:00.000Z",
    });
    assert.equal(result.status, "pending");
    assert.equal(result.approvedByAuthUserId, null);
  });
});

describe("parseVendorComplianceStatusRow", () => {
  test("maps snake_case row fields and coerces eligibility_hold to boolean", () => {
    const result = parseVendorComplianceStatusRow({
      id: DOC_ID,
      tenant_id: TENANT_ID,
      vendor_master_record_id: VENDOR_ID,
      requirement_family_id: FAMILY_ID,
      current_requirement_version_id: REQ_ID,
      current_document_id: DOC_ID,
      status: "expired",
      eligibility_hold: true,
      computed_at: "2026-08-05T00:00:00.000Z",
      computed_by: "staff",
      record_version: 3,
      created_at: "2026-08-01T00:00:00.000Z",
      updated_at: "2026-08-05T00:00:00.000Z",
    });
    assert.equal(result.eligibilityHold, true);
    assert.equal(result.status, "expired");
  });
});

describe("parseVendorComplianceEligibilityRow / parseVendorComplianceMatrixRow", () => {
  test("eligibility row tolerates null requirement/document joins", () => {
    const result = parseVendorComplianceEligibilityRow({
      requirement_family_id: FAMILY_ID,
      requirement_version_id: null,
      requirement_name: null,
      blocking_effect: null,
      document_type_code: null,
      status: "not_submitted",
      eligibility_hold: false,
      current_document_id: null,
      expiry_date: null,
      computed_at: "2026-08-05T00:00:00.000Z",
    });
    assert.equal(result.eligibilityHold, false);
    assert.equal(result.requirementName, null);
  });

  test("matrix row maps the joined vendor legal name", () => {
    const result = parseVendorComplianceMatrixRow({
      status_id: DOC_ID,
      vendor_master_record_id: VENDOR_ID,
      vendor_legal_name: "PT Contoso Trucking",
      requirement_family_id: FAMILY_ID,
      requirement_version_id: REQ_ID,
      requirement_name: "Business License",
      blocking_effect: "blocking",
      document_type_code: "vendor_compliance_document",
      status: "expiring_soon",
      eligibility_hold: false,
      current_document_id: DOC_ID,
      expiry_date: "2026-09-01",
      computed_at: "2026-08-05T00:00:00.000Z",
    });
    assert.equal(result.vendorLegalName, "PT Contoso Trucking");
    assert.equal(result.status, "expiring_soon");
  });
});

describe("mutation input schemas", () => {
  test("CreateVendorComplianceRequirementDraftInputSchema rejects an empty name", () => {
    assert.throws(() =>
      CreateVendorComplianceRequirementDraftInputSchema.parse({
        tenantId: TENANT_ID,
        documentTypeCode: "vendor_compliance_document",
        name: "",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "staff",
      }),
    );
  });

  test("CreateVendorComplianceRequirementDraftInputSchema rejects a non-positive reminder offset", () => {
    assert.throws(() =>
      CreateVendorComplianceRequirementDraftInputSchema.parse({
        tenantId: TENANT_ID,
        documentTypeCode: "vendor_compliance_document",
        name: "Business License",
        reminderOffsets: [30, 0],
        actorAuthUserId: ACTOR_ID,
        actorLabel: "staff",
      }),
    );
  });

  test("SubmitVendorComplianceDocumentInputSchema accepts a minimal valid payload", () => {
    const parsed = SubmitVendorComplianceDocumentInputSchema.parse({
      vendorMasterRecordId: VENDOR_ID,
      requirementVersionId: REQ_ID,
      fileId: FILE_ID,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "staff",
    });
    assert.equal(parsed.fileId, FILE_ID);
  });

  test("RequestVendorComplianceWaiverInputSchema rejects an empty reason", () => {
    assert.throws(() =>
      RequestVendorComplianceWaiverInputSchema.parse({
        requirementVersionId: REQ_ID,
        vendorMasterRecordId: VENDOR_ID,
        reason: "",
        validFrom: "2026-08-01",
        validUntil: "2026-08-31",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "staff",
      }),
    );
  });
});
