/** HDN-376 (API Compatibility Audit, ISS-2026-147 item 1): route-level HTTP-layer coverage for POST /api/v1/vendor/assignments/{invitationId}/decline. */
import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { installRpcFetchStub, okAuthRow } from "./support/rpc-fetch-stub.ts";
import { POST } from "../../../app/api/v1/vendor/assignments/[invitationId]/decline/route.ts";

const INVITATION_ID = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";
const VENDOR_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const params = Promise.resolve({ invitationId: INVITATION_ID });

describe("POST /api/v1/vendor/assignments/{invitationId}/decline", () => {
  test("missing Authorization header -> 401 unauthenticated", async () => {
    const stub = installRpcFetchStub({});
    try {
      const response = await POST(new Request(`http://localhost/api/v1/vendor/assignments/${INVITATION_ID}/decline`, { method: "POST", body: "{}" }), { params });
      assert.equal(response.status, 401);
    } finally {
      stub.restore();
    }
  });

  test("not a vendor-scoped key -> 403 forbidden_scope", async () => {
    const stub = installRpcFetchStub({ authenticate_and_authorize_api_request: { data: okAuthRow({ vendorMasterRecordId: null }) } });
    try {
      const response = await POST(
        new Request(`http://localhost/api/v1/vendor/assignments/${INVITATION_ID}/decline`, { method: "POST", headers: { authorization: "Bearer cgk_test_not_vendor" }, body: "{}" }),
        { params },
      );
      assert.equal(response.status, 403);
    } finally {
      stub.restore();
    }
  });

  test("malformed expectedVersion -> 400 invalid_expected_version (HDN-376 Defect B regression), never reaches the mutation RPC", async () => {
    const stub = installRpcFetchStub({ authenticate_and_authorize_api_request: { data: okAuthRow({ vendorMasterRecordId: VENDOR_ID }) } });
    try {
      const response = await POST(
        new Request(`http://localhost/api/v1/vendor/assignments/${INVITATION_ID}/decline`, {
          method: "POST",
          headers: { authorization: "Bearer cgk_test_vendor" },
          body: JSON.stringify({ reason: "no longer available" }),
        }),
        { params },
      );
      assert.equal(response.status, 400);
      const body = (await response.json()) as { error: { code: string } };
      assert.equal(body.error.code, "invalid_expected_version");
      assert.equal(stub.calls.some((c) => c.fn === "decline_vendor_assignment_invitation_via_vendor_api"), false);
    } finally {
      stub.restore();
    }
  });

  test("an empty/missing reason -> 422, rejected by the mutation wrapper's own client-side Zod validation (reason: z.string().min(1)) before ever reaching the RPC -- the route itself does not pre-validate reason, but its own mutation function does, so the RPC's dedicated reason_required error path is unreachable via this route today (double-layered validation, not a live gap: both layers agree an empty reason is rejected)", async () => {
    const stub = installRpcFetchStub({
      authenticate_and_authorize_api_request: { data: okAuthRow({ vendorMasterRecordId: VENDOR_ID }) },
    });
    try {
      const response = await POST(
        new Request(`http://localhost/api/v1/vendor/assignments/${INVITATION_ID}/decline`, {
          method: "POST",
          headers: { authorization: "Bearer cgk_test_vendor" },
          body: JSON.stringify({ expectedVersion: 1 }),
        }),
        { params },
      );
      assert.equal(response.status, 422);
      const body = (await response.json()) as { error: { code: string } };
      assert.equal(body.error.code, "mutation_failed");
      assert.equal(stub.calls.some((c) => c.fn === "decline_vendor_assignment_invitation_via_vendor_api"), false);
    } finally {
      stub.restore();
    }
  });

  test("a valid decline returns 200 with the updated invitation and decline reason", async () => {
    const stub = installRpcFetchStub({
      authenticate_and_authorize_api_request: { data: okAuthRow({ vendorMasterRecordId: VENDOR_ID }) },
      decline_vendor_assignment_invitation_via_vendor_api: {
        data: [
          {
            id: INVITATION_ID,
            tenant_id: "22222222-2222-4222-8222-222222222222",
            shipment_order_id: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
            vendor_master_id: VENDOR_ID,
            status: "declined",
            decline_reason: "no capacity this week",
            record_version: 2,
          },
        ],
      },
    });
    try {
      const response = await POST(
        new Request(`http://localhost/api/v1/vendor/assignments/${INVITATION_ID}/decline`, {
          method: "POST",
          headers: { authorization: "Bearer cgk_test_vendor" },
          body: JSON.stringify({ expectedVersion: 1, reason: "no capacity this week" }),
        }),
        { params },
      );
      assert.equal(response.status, 200);
      const body = (await response.json()) as { invitation: { status: string; declineReason: string } };
      assert.equal(body.invitation.status, "declined");
      assert.equal(body.invitation.declineReason, "no capacity this week");
    } finally {
      stub.restore();
    }
  });
});
