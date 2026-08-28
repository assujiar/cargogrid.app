/** HDN-376 (API Compatibility Audit, ISS-2026-147 item 1): route-level HTTP-layer coverage for POST /api/v1/vendor/rfqs/{rfqInvitationId}/response. */
import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { installRpcFetchStub, okAuthRow, deniedAuthRow } from "./support/rpc-fetch-stub.ts";
import { POST } from "../../../app/api/v1/vendor/rfqs/[rfqInvitationId]/response/route.ts";

const RFQ_INVITATION_ID = "99999999-9999-4999-8999-999999999999";
const VENDOR_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const params = Promise.resolve({ rfqInvitationId: RFQ_INVITATION_ID });
const BODY = JSON.stringify({ currency: "USD", totalAmount: 1000, vendorConfirmed: true });

describe("POST /api/v1/vendor/rfqs/{rfqInvitationId}/response", () => {
  test("missing Authorization header -> 401 unauthenticated", async () => {
    const stub = installRpcFetchStub({});
    try {
      const response = await POST(new Request(`http://localhost/api/v1/vendor/rfqs/${RFQ_INVITATION_ID}/response`, { method: "POST", body: BODY }), { params });
      assert.equal(response.status, 401);
    } finally {
      stub.restore();
    }
  });

  test("not a vendor-scoped key (vendorMasterRecordId null) -> 403 forbidden_scope before the idempotency-key check even runs", async () => {
    const stub = installRpcFetchStub({ authenticate_and_authorize_api_request: { data: okAuthRow({ vendorMasterRecordId: null }) } });
    try {
      const response = await POST(
        new Request(`http://localhost/api/v1/vendor/rfqs/${RFQ_INVITATION_ID}/response`, { method: "POST", headers: { authorization: "Bearer cgk_test_not_vendor" }, body: BODY }),
        { params },
      );
      assert.equal(response.status, 403);
      const body = (await response.json()) as { error: { code: string } };
      assert.equal(body.error.code, "forbidden_scope");
    } finally {
      stub.restore();
    }
  });

  test("ISS-2026-214: a malformed (non-uuid) rfqInvitationId -> 400 invalid_path_parameter, never reaches submit_rfq_response_via_vendor_api (previously leaked a raw ZodError issue array as a 422 mutation_failed message), and takes priority over the missing-Idempotency-Key check", async () => {
    const stub = installRpcFetchStub({ authenticate_and_authorize_api_request: { data: okAuthRow({ vendorMasterRecordId: VENDOR_ID }) } });
    try {
      const response = await POST(
        new Request(`http://localhost/api/v1/vendor/rfqs/not-a-uuid/response`, { method: "POST", headers: { authorization: "Bearer cgk_test_vendor" }, body: BODY }),
        { params: Promise.resolve({ rfqInvitationId: "not-a-uuid" }) },
      );
      assert.equal(response.status, 400);
      const body = (await response.json()) as { error: { code: string; message: string } };
      assert.equal(body.error.code, "invalid_path_parameter");
      assert.doesNotMatch(body.error.message, /"code":|"issues":|ZodError/);
      assert.equal(stub.calls.some((c) => c.fn === "submit_rfq_response_via_vendor_api"), false);
    } finally {
      stub.restore();
    }
  });

  test("missing Idempotency-Key header -> 400 missing_idempotency_key (HDN-376 Defect A regression: previously the wrong-domain code webhook_missing_idempotency_key)", async () => {
    const stub = installRpcFetchStub({ authenticate_and_authorize_api_request: { data: okAuthRow({ vendorMasterRecordId: VENDOR_ID }) } });
    try {
      const response = await POST(
        new Request(`http://localhost/api/v1/vendor/rfqs/${RFQ_INVITATION_ID}/response`, { method: "POST", headers: { authorization: "Bearer cgk_test_vendor" }, body: BODY }),
        { params },
      );
      assert.equal(response.status, 400);
      const body = (await response.json()) as { error: { code: string } };
      assert.equal(body.error.code, "missing_idempotency_key");
      assert.equal(stub.calls.some((c) => c.fn === "submit_rfq_response_via_vendor_api"), false);
    } finally {
      stub.restore();
    }
  });

  test("an invitation that does not exist for this vendor -> 404 rfq_invitation_not_found", async () => {
    const stub = installRpcFetchStub({
      authenticate_and_authorize_api_request: { data: okAuthRow({ vendorMasterRecordId: VENDOR_ID }) },
      submit_rfq_response_via_vendor_api: { error: { message: "rfq_invitation_not_found: no rfq invitation for this vendor" } },
    });
    try {
      const response = await POST(
        new Request(`http://localhost/api/v1/vendor/rfqs/${RFQ_INVITATION_ID}/response`, {
          method: "POST",
          headers: { authorization: "Bearer cgk_test_vendor", "idempotency-key": "idem-rfq-001" },
          body: BODY,
        }),
        { params },
      );
      assert.equal(response.status, 404);
      const errBody = (await response.json()) as { error: { code: string } };
      assert.equal(errBody.error.code, "rfq_invitation_not_found");
    } finally {
      stub.restore();
    }
  });

  test("a valid response submission returns 201 with the created RFQ response", async () => {
    const stub = installRpcFetchStub({
      authenticate_and_authorize_api_request: { data: okAuthRow({ vendorMasterRecordId: VENDOR_ID }) },
      submit_rfq_response_via_vendor_api: {
        data: [
          {
            id: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
            tenant_id: "22222222-2222-4222-8222-222222222222",
            rfq_id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
            rfq_invitation_id: RFQ_INVITATION_ID,
            version: 1,
            status: "submitted",
            currency: "USD",
            total_amount: 1000,
            validity_until: null,
            lead_time_days: null,
            capture_mode: "vendor_api",
            late_capture: false,
            created_at: "2026-08-24T00:00:00.000Z",
          },
        ],
      },
    });
    try {
      const response = await POST(
        new Request(`http://localhost/api/v1/vendor/rfqs/${RFQ_INVITATION_ID}/response`, {
          method: "POST",
          headers: { authorization: "Bearer cgk_test_vendor", "idempotency-key": "idem-rfq-001" },
          body: BODY,
        }),
        { params },
      );
      assert.equal(response.status, 201);
      const body = (await response.json()) as { response: { status: string; captureMode: string } };
      assert.equal(body.response.status, "submitted");
      assert.equal(body.response.captureMode, "vendor_api");
    } finally {
      stub.restore();
    }
  });
});
