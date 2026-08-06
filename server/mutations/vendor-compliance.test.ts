import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createVendorComplianceRequirementDraft,
  publishVendorComplianceRequirement,
  submitVendorComplianceDocument,
  decideVendorComplianceDocument,
  accessVendorComplianceDocumentEvidence,
  requestVendorComplianceWaiver,
  decideVendorComplianceWaiver,
  expireVendorComplianceWaivers,
  recalculateVendorComplianceStatus,
  recalculateTenantVendorComplianceStatus,
  VendorComplianceMutationError,
  type VendorComplianceMutationRpcClient,
} from "./vendor-compliance.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VENDOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const REQ_ID = "123e4567-e89b-12d3-a456-426614174000";
const FAMILY_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const DOC_ID = "523e4567-e89b-12d3-a456-426614174000";
const FILE_ID = "723e4567-e89b-12d3-a456-426614174000";
const WAIVER_ID = "823e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: VendorComplianceMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as VendorComplianceMutationRpcClient;
  return { client, calls };
}

const REQUIREMENT_ROW = {
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
  status: "draft",
  supersedes_version_id: null,
  effective_from: "2026-08-05T00:00:00.000Z",
  record_version: 1,
  created_by: "staff",
  created_at: "2026-08-05T00:00:00.000Z",
  updated_at: "2026-08-05T00:00:00.000Z",
};

const DOCUMENT_ROW = {
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
  verification_status: "pending",
  verified_by: null,
  verified_by_auth_user_id: null,
  verified_at: null,
  rejection_reason: null,
  record_version: 1,
  created_by: "staff",
  created_at: "2026-08-05T00:00:00.000Z",
  updated_at: "2026-08-05T00:00:00.000Z",
};

const WAIVER_ROW = {
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
};

describe("createVendorComplianceRequirementDraft", () => {
  test("calls create_vendor_compliance_requirement_draft with mapped snake_case args", async () => {
    const { client, calls } = fakeRpcClient({ data: [REQUIREMENT_ROW], error: null });
    const result = await createVendorComplianceRequirementDraft(client, {
      tenantId: TENANT_ID,
      documentTypeCode: "vendor_compliance_document",
      name: "Business License",
      blockingEffect: "blocking",
      requiresExpiry: true,
      reminderOffsets: [30, 14, 7],
      actorAuthUserId: ACTOR_ID,
      actorLabel: "staff",
    });
    assert.equal(calls[0]?.fn, "create_vendor_compliance_requirement_draft");
    assert.equal(calls[0]?.args.p_name, "Business License");
    assert.deepEqual(calls[0]?.args.p_reminder_offsets, [30, 14, 7]);
    assert.equal(result.status, "draft");
  });

  test("classifies a known error code from the rpc error message", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "document_type_not_registered: xyz is not registered" } });
    await assert.rejects(
      () => createVendorComplianceRequirementDraft(client, { tenantId: TENANT_ID, documentTypeCode: "xyz", name: "x", actorAuthUserId: ACTOR_ID, actorLabel: "staff" }),
      (error: unknown) => {
        assert.ok(error instanceof VendorComplianceMutationError);
        assert.equal(error.code, "document_type_not_registered");
        return true;
      },
    );
  });

  test("falls back to mutation_failed for an unrecognized error prefix", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "some_unmapped_db_error: oops" } });
    await assert.rejects(
      () => createVendorComplianceRequirementDraft(client, { tenantId: TENANT_ID, documentTypeCode: "x", name: "x", actorAuthUserId: ACTOR_ID, actorLabel: "staff" }),
      (error: unknown) => {
        assert.ok(error instanceof VendorComplianceMutationError);
        assert.equal(error.code, "mutation_failed");
        return true;
      },
    );
  });
});

describe("publishVendorComplianceRequirement", () => {
  test("forwards supersedesVersionId as null when omitted", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...REQUIREMENT_ROW, status: "published" }], error: null });
    const result = await publishVendorComplianceRequirement(client, { requirementVersionId: REQ_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "approver" });
    assert.equal(calls[0]?.args.p_supersedes_version_id, null);
    assert.equal(result.status, "published");
  });
});

describe("submitVendorComplianceDocument", () => {
  test("maps evidence file and date fields", async () => {
    const { client, calls } = fakeRpcClient({ data: [DOCUMENT_ROW], error: null });
    const result = await submitVendorComplianceDocument(client, {
      vendorMasterRecordId: VENDOR_ID,
      requirementVersionId: REQ_ID,
      fileId: FILE_ID,
      issueDate: "2026-01-01",
      expiryDate: "2027-01-01",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "staff",
    });
    assert.equal(calls[0]?.fn, "submit_vendor_compliance_document");
    assert.equal(calls[0]?.args.p_file_id, FILE_ID);
    assert.equal(result.verificationStatus, "pending");
  });

  test("classifies compliance_unsafe_evidence", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "compliance_unsafe_evidence: evidence file X has scan status pending" } });
    await assert.rejects(
      () => submitVendorComplianceDocument(client, { vendorMasterRecordId: VENDOR_ID, requirementVersionId: REQ_ID, fileId: FILE_ID, actorAuthUserId: ACTOR_ID, actorLabel: "staff" }),
      (error: unknown) => {
        assert.ok(error instanceof VendorComplianceMutationError);
        assert.equal(error.code, "compliance_unsafe_evidence");
        return true;
      },
    );
  });
});

describe("decideVendorComplianceDocument", () => {
  test("maps decision and rejection reason", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...DOCUMENT_ROW, verification_status: "rejected", rejection_reason: "expired evidence" }], error: null });
    const result = await decideVendorComplianceDocument(client, { documentId: DOC_ID, expectedVersion: 1, decision: "rejected", rejectionReason: "expired evidence", actorAuthUserId: ACTOR_ID, actorLabel: "approver" });
    assert.equal(calls[0]?.args.p_decision, "rejected");
    assert.equal(result.rejectionReason, "expired evidence");
  });
});

describe("accessVendorComplianceDocumentEvidence", () => {
  test("maps a granted result including file metadata", async () => {
    const { client, calls } = fakeRpcClient({
      data: [
        {
          file_id: FILE_ID,
          original_filename: "business-license.pdf",
          mime_type: "application/pdf",
          size_bytes: 51200,
          malware_scan_status: "clean",
          classification: "internal",
          legal_hold: false,
          uploaded_at: "2026-01-01T00:00:00.000Z",
          access_result: "granted",
          access_reason: null,
        },
      ],
      error: null,
    });
    const result = await accessVendorComplianceDocumentEvidence(client, { documentId: DOC_ID, accessType: "metadata_view", actorAuthUserId: ACTOR_ID, actorLabel: "approver" });
    assert.equal(calls[0]?.fn, "access_vendor_compliance_document_evidence");
    assert.equal(calls[0]?.args.p_access_type, "metadata_view");
    assert.equal(result.accessResult, "granted");
    assert.equal(result.originalFilename, "business-license.pdf");
  });

  test("maps a denied result with file-identifying fields nulled out, without throwing", async () => {
    const { client } = fakeRpcClient({
      data: [
        {
          file_id: FILE_ID,
          original_filename: null,
          mime_type: null,
          size_bytes: null,
          malware_scan_status: null,
          classification: null,
          legal_hold: null,
          uploaded_at: null,
          access_result: "denied",
          access_reason: "document_not_yet_scanned",
        },
      ],
      error: null,
    });
    const result = await accessVendorComplianceDocumentEvidence(client, { documentId: DOC_ID, accessType: "download", actorAuthUserId: ACTOR_ID, actorLabel: "approver" });
    assert.equal(result.accessResult, "denied");
    assert.equal(result.accessReason, "document_not_yet_scanned");
    assert.equal(result.originalFilename, null);
  });

  test("classifies insufficient_authority for an actor lacking PRC:Download", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity X lacks PRC:Download" } });
    await assert.rejects(
      () => accessVendorComplianceDocumentEvidence(client, { documentId: DOC_ID, accessType: "metadata_view", actorAuthUserId: ACTOR_ID, actorLabel: "viewer" }),
      (error: unknown) => {
        assert.ok(error instanceof VendorComplianceMutationError);
        assert.equal(error.code, "insufficient_authority");
        return true;
      },
    );
  });
});

describe("requestVendorComplianceWaiver / decideVendorComplianceWaiver", () => {
  test("request maps validity window fields", async () => {
    const { client, calls } = fakeRpcClient({ data: [WAIVER_ROW], error: null });
    const result = await requestVendorComplianceWaiver(client, {
      requirementVersionId: REQ_ID,
      vendorMasterRecordId: VENDOR_ID,
      reason: "operational exception",
      validFrom: "2026-08-01",
      validUntil: "2026-08-31",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "staff",
    });
    assert.equal(calls[0]?.args.p_valid_from, "2026-08-01");
    assert.equal(result.status, "pending");
  });

  test("decide classifies self_approval_not_allowed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "self_approval_not_allowed: identity X requested waiver Y and may not also decide it" } });
    await assert.rejects(
      () => decideVendorComplianceWaiver(client, { waiverId: WAIVER_ID, expectedVersion: 1, decision: "approved", actorAuthUserId: ACTOR_ID, actorLabel: "staff" }),
      (error: unknown) => {
        assert.ok(error instanceof VendorComplianceMutationError);
        assert.equal(error.code, "self_approval_not_allowed");
        return true;
      },
    );
  });
});

describe("expireVendorComplianceWaivers / recalculateTenantVendorComplianceStatus", () => {
  test("expireVendorComplianceWaivers maps the bounded sweep response shape", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ expired_count: 3, more_remaining: false }], error: null });
    const result = await expireVendorComplianceWaivers(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "manager" });
    assert.equal(calls[0]?.fn, "expire_vendor_compliance_waivers");
    assert.equal(result.count, 3);
    assert.equal(result.moreRemaining, false);
  });

  test("recalculateTenantVendorComplianceStatus maps vendors_recalculated/more_remaining", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ vendors_recalculated: 12, more_remaining: true }], error: null });
    const result = await recalculateTenantVendorComplianceStatus(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "manager" });
    assert.equal(calls[0]?.fn, "recalculate_tenant_vendor_compliance_status");
    assert.equal(result.count, 12);
    assert.equal(result.moreRemaining, true);
  });
});

describe("recalculateVendorComplianceStatus", () => {
  test("maps a set of returned status rows", async () => {
    const { client, calls } = fakeRpcClient({
      data: [
        {
          id: DOC_ID,
          tenant_id: TENANT_ID,
          vendor_master_record_id: VENDOR_ID,
          requirement_family_id: FAMILY_ID,
          current_requirement_version_id: REQ_ID,
          current_document_id: DOC_ID,
          status: "verified",
          eligibility_hold: false,
          computed_at: "2026-08-05T00:00:00.000Z",
          computed_by: "staff",
          record_version: 1,
          created_at: "2026-08-05T00:00:00.000Z",
          updated_at: "2026-08-05T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const result = await recalculateVendorComplianceStatus(client, { vendorMasterRecordId: VENDOR_ID, actorAuthUserId: ACTOR_ID, actorLabel: "staff" });
    assert.equal(calls[0]?.fn, "recalculate_vendor_compliance_status");
    assert.equal(result[0]?.status, "verified");
  });
});
