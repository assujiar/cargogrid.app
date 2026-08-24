/** HDN-376 (API Compatibility Audit, ISS-2026-147 item 1): route-level HTTP-layer coverage for POST /api/v1/vendor/assignments/{invitationId}/accept. */
import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { installRpcFetchStub, okAuthRow } from "./support/rpc-fetch-stub.ts";
import { POST } from "../../../app/api/v1/vendor/assignments/[invitationId]/accept/route.ts";

const INVITATION_ID = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";
const VENDOR_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const params = Promise.resolve({ invitationId: INVITATION_ID });

describe("POST /api/v1/vendor/assignments/{invitationId}/accept", () => {
  test("missing Authorization header -> 401 unauthenticated", async () => {
    const stub = installRpcFetchStub({});
    try {
      const response = await POST(new Request(`http://localhost/api/v1/vendor/assignments/${INVITATION_ID}/accept`, { method: "POST", body: "{}" }), { params });
      assert.equal(response.status, 401);
    } finally {
      stub.restore();
    }
  });

  test("not a vendor-scoped key -> 403 forbidden_scope, never reaches the malformed-body check or the mutation RPC", async () => {
    const stub = installRpcFetchStub({ authenticate_and_authorize_api_request: { data: okAuthRow({ vendorMasterRecordId: null }) } });
    try {
      const response = await POST(
        new Request(`http://localhost/api/v1/vendor/assignments/${INVITATION_ID}/accept`, { method: "POST", headers: { authorization: "Bearer cgk_test_not_vendor" }, body: "{}" }),
        { params },
      );
      assert.equal(response.status, 403);
      assert.equal(stub.calls.some((c) => c.fn === "accept_vendor_assignment_invitation_via_vendor_api"), false);
    } finally {
      stub.restore();
    }
  });

  test("malformed expectedVersion -> 400 invalid_expected_version (HDN-376 Defect B regression: previously the wrong code stale_version, indistinguishable from a real 409 conflict)", async () => {
    const stub = installRpcFetchStub({ authenticate_and_authorize_api_request: { data: okAuthRow({ vendorMasterRecordId: VENDOR_ID }) } });
    try {
      const response = await POST(
        new Request(`http://localhost/api/v1/vendor/assignments/${INVITATION_ID}/accept`, { method: "POST", headers: { authorization: "Bearer cgk_test_vendor" }, body: "{}" }),
        { params },
      );
      assert.equal(response.status, 400);
      const body = (await response.json()) as { error: { code: string } };
      assert.equal(body.error.code, "invalid_expected_version");
    } finally {
      stub.restore();
    }
  });

  test("a genuine optimistic-concurrency conflict -> 409 stale_version, distinct from the 400 malformed-input case", async () => {
    const stub = installRpcFetchStub({
      authenticate_and_authorize_api_request: { data: okAuthRow({ vendorMasterRecordId: VENDOR_ID }) },
      accept_vendor_assignment_invitation_via_vendor_api: { error: { message: "stale_version: vendor assignment invitation expected version 1 but found 2" } },
    });
    try {
      const response = await POST(
        new Request(`http://localhost/api/v1/vendor/assignments/${INVITATION_ID}/accept`, {
          method: "POST",
          headers: { authorization: "Bearer cgk_test_vendor" },
          body: JSON.stringify({ expectedVersion: 1 }),
        }),
        { params },
      );
      assert.equal(response.status, 409);
      const body = (await response.json()) as { error: { code: string } };
      assert.equal(body.error.code, "stale_version");
    } finally {
      stub.restore();
    }
  });

  test("an invitation not belonging to this vendor -> 404 vendor_assignment_invitation_not_found", async () => {
    const stub = installRpcFetchStub({
      authenticate_and_authorize_api_request: { data: okAuthRow({ vendorMasterRecordId: VENDOR_ID }) },
      accept_vendor_assignment_invitation_via_vendor_api: { error: { message: "vendor_assignment_invitation_not_found: no invitation for this vendor" } },
    });
    try {
      const response = await POST(
        new Request(`http://localhost/api/v1/vendor/assignments/${INVITATION_ID}/accept`, {
          method: "POST",
          headers: { authorization: "Bearer cgk_test_vendor" },
          body: JSON.stringify({ expectedVersion: 1 }),
        }),
        { params },
      );
      assert.equal(response.status, 404);
    } finally {
      stub.restore();
    }
  });

  test("a valid accept returns 200 with the updated invitation", async () => {
    const stub = installRpcFetchStub({
      authenticate_and_authorize_api_request: { data: okAuthRow({ vendorMasterRecordId: VENDOR_ID }) },
      accept_vendor_assignment_invitation_via_vendor_api: {
        data: [
          {
            id: INVITATION_ID,
            tenant_id: "22222222-2222-4222-8222-222222222222",
            shipment_order_id: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
            vendor_master_id: VENDOR_ID,
            status: "accepted",
            decline_reason: null,
            record_version: 2,
          },
        ],
      },
    });
    try {
      const response = await POST(
        new Request(`http://localhost/api/v1/vendor/assignments/${INVITATION_ID}/accept`, {
          method: "POST",
          headers: { authorization: "Bearer cgk_test_vendor" },
          body: JSON.stringify({ expectedVersion: 1 }),
        }),
        { params },
      );
      assert.equal(response.status, 200);
      const body = (await response.json()) as { invitation: { status: string; recordVersion: number } };
      assert.equal(body.invitation.status, "accepted");
      assert.equal(body.invitation.recordVersion, 2);
    } finally {
      stub.restore();
    }
  });
});
