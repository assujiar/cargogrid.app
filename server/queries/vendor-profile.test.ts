import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  getVendorProfile,
  listVendorProfiles,
  listVendorContacts,
  searchVendorDuplicateCandidates,
  getVendorLifecycleHistory,
  VendorProfileQueryError,
  type VendorProfileQueryClient,
} from "./vendor-profile.ts";

const MASTER_RECORD_ID = "223e4567-e89b-12d3-a456-426614174000";
const TENANT_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: VendorProfileQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as VendorProfileQueryClient;
  return { client, calls };
}

describe("getVendorProfile", () => {
  test("maps the detail row", async () => {
    const { client } = fakeRpcClient({
      data: [
        {
          master_record_id: MASTER_RECORD_ID,
          tenant_id: TENANT_ID,
          vendor_code: "VND-2026-000001",
          legal_name: "PT Contoso Logistik",
          trade_name: null,
          legal_entity_type: "PT",
          business_registration_number: null,
          vendor_category: "trucking",
          payment_term_days: 30,
          intake_source: "staff_created",
          lifecycle_status: "draft",
          revision_reason: null,
          suspend_reason: null,
          blacklist_reason: null,
          blacklist_evidence_ref: null,
          record_version: 1,
          created_by: "staff",
          created_at: "2026-08-05T00:00:00.000Z",
          updated_at: "2026-08-05T00:00:00.000Z",
          contact_count: 0,
          address_count: 0,
          service_count: 0,
          coverage_count: 0,
          pending_duplicate_count: 0,
        },
      ],
      error: null,
    });
    const profile = await getVendorProfile(client, MASTER_RECORD_ID, ACTOR_ID);
    assert.equal(profile.vendorCode, "VND-2026-000001");
  });

  test("throws VendorProfileQueryError when the RPC returns no row", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    await assert.rejects(() => getVendorProfile(client, MASTER_RECORD_ID, ACTOR_ID), VendorProfileQueryError);
  });

  test("throws VendorProfileQueryError translating an RPC error (e.g. insufficient_authority)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks PRC:View" } });
    await assert.rejects(() => getVendorProfile(client, MASTER_RECORD_ID, ACTOR_ID), /insufficient_authority/);
  });
});

describe("listVendorProfiles", () => {
  test("defaults limit/afterCode/statusFilter/search to sane RPC args", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listVendorProfiles(client, TENANT_ID, ACTOR_ID);
    assert.equal(calls[0]?.fn, "list_vendor_profiles");
    assert.equal(calls[0]?.args.p_status_filter, null);
    assert.equal(calls[0]?.args.p_limit, 50);
  });

  test("passes through an explicit status filter/search/cursor", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listVendorProfiles(client, TENANT_ID, ACTOR_ID, { statusFilter: "active", search: "contoso", limit: 10, afterCode: "VND-2026-000005" });
    assert.equal(calls[0]?.args.p_status_filter, "active");
    assert.equal(calls[0]?.args.p_search, "contoso");
    assert.equal(calls[0]?.args.p_after_code, "VND-2026-000005");
  });

  test("maps returned rows", async () => {
    const { client } = fakeRpcClient({
      data: [
        {
          master_record_id: MASTER_RECORD_ID,
          vendor_code: "VND-2026-000001",
          legal_name: "PT Contoso Logistik",
          trade_name: null,
          vendor_category: "trucking",
          lifecycle_status: "active",
          intake_source: "staff_created",
          record_version: 1,
          created_at: "2026-08-05T00:00:00.000Z",
          updated_at: "2026-08-05T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const rows = await listVendorProfiles(client, TENANT_ID, ACTOR_ID);
    assert.equal(rows.length, 1);
    assert.equal(rows[0]?.lifecycleStatus, "active");
  });
});

describe("listVendorContacts", () => {
  test("maps masked contact rows (email/phone null)", async () => {
    const { client } = fakeRpcClient({
      data: [{ id: MASTER_RECORD_ID, master_record_id: MASTER_RECORD_ID, name: "Jane Vendor", title: null, email: null, phone: null, is_primary: true, record_version: 1, created_at: "2026-08-05T00:00:00.000Z" }],
      error: null,
    });
    const rows = await listVendorContacts(client, MASTER_RECORD_ID, ACTOR_ID);
    assert.equal(rows[0]?.email, null);
    assert.equal(rows[0]?.name, "Jane Vendor");
  });
});

describe("searchVendorDuplicateCandidates", () => {
  test("passes the default limit and maps score rows", async () => {
    const { client, calls } = fakeRpcClient({
      data: [{ master_record_id: MASTER_RECORD_ID, vendor_code: "VND-2026-000001", legal_name: "PT Nusantara Cargo Ekspres", trade_name: null, similarity_score: 0.8 }],
      error: null,
    });
    const rows = await searchVendorDuplicateCandidates(client, TENANT_ID, "PT Nusantara Cargo Express", null, ACTOR_ID);
    assert.equal(calls[0]?.args.p_limit, 10);
    assert.equal(rows[0]?.similarityScore, 0.8);
  });
});

describe("getVendorLifecycleHistory", () => {
  test("maps lifecycle event rows in RPC order", async () => {
    const { client } = fakeRpcClient({
      data: [
        { id: MASTER_RECORD_ID, master_record_id: MASTER_RECORD_ID, from_status: "none", to_status: "draft", reason: null, evidence_ref: null, actor_label: "staff", occurred_at: "2026-08-05T00:00:00.000Z" },
        { id: TENANT_ID, master_record_id: MASTER_RECORD_ID, from_status: "draft", to_status: "submitted", reason: null, evidence_ref: null, actor_label: "staff", occurred_at: "2026-08-05T00:01:00.000Z" },
      ],
      error: null,
    });
    const events = await getVendorLifecycleHistory(client, MASTER_RECORD_ID, ACTOR_ID);
    assert.equal(events.length, 2);
    assert.equal(events[1]?.toStatus, "submitted");
  });
});
