import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  getVendorComplianceRequirement,
  listVendorComplianceRequirements,
  listVendorComplianceDocuments,
  listVendorComplianceDocumentVersions,
  getVendorComplianceEligibility,
  listTenantVendorComplianceMatrix,
  VendorComplianceQueryError,
  type VendorComplianceQueryClient,
} from "./vendor-compliance.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VENDOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const REQ_ID = "123e4567-e89b-12d3-a456-426614174000";
const FAMILY_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const DOC_ID = "523e4567-e89b-12d3-a456-426614174000";
const FILE_ID = "723e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: VendorComplianceQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as VendorComplianceQueryClient;
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
  status: "published",
  supersedes_version_id: null,
  effective_from: "2026-08-05T00:00:00.000Z",
  record_version: 1,
  created_by: "staff",
  created_at: "2026-08-05T00:00:00.000Z",
  updated_at: "2026-08-05T00:00:00.000Z",
};

describe("getVendorComplianceRequirement", () => {
  test("calls get_vendor_compliance_requirement and parses the row", async () => {
    const { client, calls } = fakeRpcClient({ data: [REQUIREMENT_ROW], error: null });
    const result = await getVendorComplianceRequirement(client, REQ_ID, ACTOR_ID);
    assert.equal(calls[0]?.fn, "get_vendor_compliance_requirement");
    assert.equal(calls[0]?.args.p_requirement_version_id, REQ_ID);
    assert.equal(result.name, "Business License");
  });

  test("throws VendorComplianceQueryError on rpc error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: nope" } });
    await assert.rejects(() => getVendorComplianceRequirement(client, REQ_ID, ACTOR_ID), VendorComplianceQueryError);
  });

  test("throws VendorComplianceQueryError when no row is returned", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    await assert.rejects(() => getVendorComplianceRequirement(client, REQ_ID, ACTOR_ID), VendorComplianceQueryError);
  });
});

describe("listVendorComplianceRequirements", () => {
  test("passes through cursor/filter args with defaults applied", async () => {
    const { client, calls } = fakeRpcClient({ data: [REQUIREMENT_ROW], error: null });
    const result = await listVendorComplianceRequirements(client, TENANT_ID, ACTOR_ID, { statusFilter: "published" });
    assert.equal(calls[0]?.fn, "list_vendor_compliance_requirements");
    assert.equal(calls[0]?.args.p_status_filter, "published");
    assert.equal(calls[0]?.args.p_limit, 50);
    assert.equal(result.length, 1);
  });
});

describe("listVendorComplianceDocuments", () => {
  test("defaults latestOnly to true", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listVendorComplianceDocuments(client, VENDOR_ID, ACTOR_ID);
    assert.equal(calls[0]?.args.p_latest_only, true);
  });
});

describe("listVendorComplianceDocumentVersions", () => {
  test("returns the full lineage ordered by version_number", async () => {
    const versionGroupId = DOC_ID;
    const docV1 = {
      id: DOC_ID,
      tenant_id: TENANT_ID,
      vendor_master_record_id: VENDOR_ID,
      requirement_version_id: REQ_ID,
      file_id: FILE_ID,
      version_group_id: versionGroupId,
      version_number: 1,
      is_latest_version: false,
      issue_date: "2026-01-01",
      expiry_date: "2027-01-01",
      verification_status: "verified",
      verified_by: "approver",
      verified_by_auth_user_id: ACTOR_ID,
      verified_at: "2026-08-05T00:00:00.000Z",
      rejection_reason: null,
      record_version: 2,
      created_by: "staff",
      created_at: "2026-01-01T00:00:00.000Z",
      updated_at: "2026-08-05T00:00:00.000Z",
    };
    const { client, calls } = fakeRpcClient({ data: [docV1], error: null });
    const result = await listVendorComplianceDocumentVersions(client, versionGroupId, ACTOR_ID);
    assert.equal(calls[0]?.fn, "list_vendor_compliance_document_versions");
    assert.equal(result[0]?.versionNumber, 1);
  });
});

describe("getVendorComplianceEligibility", () => {
  test("maps the downstream-composable eligibility rows", async () => {
    const { client, calls } = fakeRpcClient({
      data: [
        {
          requirement_family_id: FAMILY_ID,
          requirement_version_id: REQ_ID,
          requirement_name: "Business License",
          blocking_effect: "blocking",
          document_type_code: "vendor_compliance_document",
          status: "expired",
          eligibility_hold: true,
          current_document_id: DOC_ID,
          expiry_date: "2026-07-01",
          computed_at: "2026-08-05T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const result = await getVendorComplianceEligibility(client, VENDOR_ID, ACTOR_ID);
    assert.equal(calls[0]?.fn, "get_vendor_compliance_eligibility");
    assert.equal(result[0]?.eligibilityHold, true);
    assert.equal(result[0]?.reminderTierDays, null);
  });

  test("maps reminder_offsets/days_until_expiry/reminder_tier_days (fix-pass addition)", async () => {
    const { client } = fakeRpcClient({
      data: [
        {
          requirement_family_id: FAMILY_ID,
          requirement_version_id: REQ_ID,
          requirement_name: "Business License",
          blocking_effect: "blocking",
          document_type_code: "vendor_compliance_document",
          status: "expiring_soon",
          eligibility_hold: false,
          current_document_id: DOC_ID,
          expiry_date: "2026-08-16",
          reminder_offsets: [30, 14, 7],
          days_until_expiry: 10,
          reminder_tier_days: 14,
          computed_at: "2026-08-05T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const result = await getVendorComplianceEligibility(client, VENDOR_ID, ACTOR_ID);
    assert.deepEqual(result[0]?.reminderOffsets, [30, 14, 7]);
    assert.equal(result[0]?.daysUntilExpiry, 10);
    assert.equal(result[0]?.reminderTierDays, 14);
  });
});

describe("listTenantVendorComplianceMatrix", () => {
  test("defaults holdOnly to false and passes tenant scope", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listTenantVendorComplianceMatrix(client, TENANT_ID, ACTOR_ID);
    assert.equal(calls[0]?.fn, "list_tenant_vendor_compliance_matrix");
    assert.equal(calls[0]?.args.p_hold_only, false);
    assert.equal(calls[0]?.args.p_tenant_id, TENANT_ID);
  });

  test("hold_only=true is forwarded for the eligibility-hold queue view", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listTenantVendorComplianceMatrix(client, TENANT_ID, ACTOR_ID, { holdOnly: true });
    assert.equal(calls[0]?.args.p_hold_only, true);
  });
});
