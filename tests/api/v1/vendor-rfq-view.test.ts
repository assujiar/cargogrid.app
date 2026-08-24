/** HDN-376 (API Compatibility Audit, ISS-2026-147 item 1): route-level HTTP-layer coverage for GET /api/v1/vendor/rfqs/{rfqInvitationId}. */
import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { installRpcFetchStub, okAuthRow, deniedAuthRow } from "./support/rpc-fetch-stub.ts";
import { GET } from "../../../app/api/v1/vendor/rfqs/[rfqInvitationId]/route.ts";

const RFQ_INVITATION_ID = "99999999-9999-4999-8999-999999999999";
const params = Promise.resolve({ rfqInvitationId: RFQ_INVITATION_ID });
const VENDOR_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";

describe("GET /api/v1/vendor/rfqs/{rfqInvitationId}", () => {
  test("missing Authorization header -> 401 unauthenticated", async () => {
    const stub = installRpcFetchStub({});
    try {
      const response = await GET(new Request(`http://localhost/api/v1/vendor/rfqs/${RFQ_INVITATION_ID}`), { params });
      assert.equal(response.status, 401);
    } finally {
      stub.restore();
    }
  });

  test("a key lacking PRC:VendorPortal scope -> 403 forbidden_scope at the gateway", async () => {
    const stub = installRpcFetchStub({ authenticate_and_authorize_api_request: { data: deniedAuthRow("forbidden_scope") } });
    try {
      const response = await GET(new Request(`http://localhost/api/v1/vendor/rfqs/${RFQ_INVITATION_ID}`, { headers: { authorization: "Bearer cgk_test_wrong_scope" } }), { params });
      assert.equal(response.status, 403);
    } finally {
      stub.restore();
    }
  });

  test("a genuinely scoped-in key that is not vendor-bound (vendorMasterRecordId null, e.g. a customer-scoped key) -> 403 forbidden_scope, distinct route-level check before ever calling the RPC", async () => {
    const stub = installRpcFetchStub({ authenticate_and_authorize_api_request: { data: okAuthRow({ vendorMasterRecordId: null }) } });
    try {
      const response = await GET(new Request(`http://localhost/api/v1/vendor/rfqs/${RFQ_INVITATION_ID}`, { headers: { authorization: "Bearer cgk_test_not_vendor" } }), { params });
      assert.equal(response.status, 403);
      assert.equal(stub.calls.some((c) => c.fn === "get_rfq_for_vendor_api"), false);
    } finally {
      stub.restore();
    }
  });

  test("an invitation that does not exist or does not belong to this vendor -> 404 rfq_invitation_not_found (never discloses which)", async () => {
    const stub = installRpcFetchStub({
      authenticate_and_authorize_api_request: { data: okAuthRow({ vendorMasterRecordId: VENDOR_ID }) },
      get_rfq_for_vendor_api: { data: [] },
    });
    try {
      const response = await GET(new Request(`http://localhost/api/v1/vendor/rfqs/${RFQ_INVITATION_ID}`, { headers: { authorization: "Bearer cgk_test_vendor" } }), { params });
      assert.equal(response.status, 404);
      const body = (await response.json()) as { error: { code: string } };
      assert.equal(body.error.code, "rfq_invitation_not_found");
    } finally {
      stub.restore();
    }
  });

  test("a genuine, owned invitation returns 200 with the RFQ summary", async () => {
    const stub = installRpcFetchStub({
      authenticate_and_authorize_api_request: { data: okAuthRow({ vendorMasterRecordId: VENDOR_ID }) },
      get_rfq_for_vendor_api: {
        data: [
          {
            rfq_invitation_id: RFQ_INVITATION_ID,
            rfq_id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
            invitation_status: "invited",
            response_deadline_at: "2026-09-01T00:00:00.000Z",
            rfq_number: "RFQ-2026-000001",
            rfq_status: "open",
          },
        ],
      },
    });
    try {
      const response = await GET(new Request(`http://localhost/api/v1/vendor/rfqs/${RFQ_INVITATION_ID}`, { headers: { authorization: "Bearer cgk_test_vendor" } }), { params });
      assert.equal(response.status, 200);
      const body = (await response.json()) as { rfq: { rfqInvitationId: string; invitationStatus: string; rfqNumber: string } };
      assert.equal(body.rfq.rfqInvitationId, RFQ_INVITATION_ID);
      assert.equal(body.rfq.invitationStatus, "invited");
      assert.equal(body.rfq.rfqNumber, "RFQ-2026-000001");
    } finally {
      stub.restore();
    }
  });
});
