/**
 * `ISS-2026-207`: route-level proof that `app.api_versions` now has live effect on a real
 * request. Before this, the registry was audited, admin-visible, db-tested — and completely
 * inert: marking `v1` sunset changed nothing a caller could observe.
 *
 * `/api/v1/status` is used as the vehicle because it is the thinnest of the nine routes; the gate
 * lives in the shared `authorizeApiV1Request`, so proving it once proves it for all nine.
 */
import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { installRpcFetchStub, okAuthRow } from "./support/rpc-fetch-stub.ts";

import { GET } from "../../../app/api/v1/status/route.ts";

/** GET /api/v1/status renders the registry in its own body; the gate is a separate concern. */
const STATUS_BODY_HANDLERS = {
  list_api_versions: { data: [{ code: "v1", status: "active", sunset_at: null, notes: null, registered_by: "seed", created_at: "2026-01-01T00:00:00.000Z", updated_at: "2026-01-01T00:00:00.000Z" }] },
};

const BEARER = { headers: { authorization: "Bearer cg_live_testkey" } };

describe("ISS-2026-207 — the API version registry gates and signals real requests", () => {
  test("a version past its sunset date is refused with 410, and the refusal is logged", async () => {
    const stub = installRpcFetchStub({
      evaluate_api_version_request: { data: [{ decision: "gone", status: "sunset", sunset_at: "2020-01-01T00:00:00.000Z" }] },
      authenticate_and_authorize_api_request: { data: okAuthRow() },
    });
    try {
      const response = await GET(new Request("http://localhost/api/v1/status", BEARER));
      assert.equal(response.status, 410);
      const body = (await response.json()) as { error: { code: string } };
      assert.equal(body.error.code, "api_version_gone");

      // The refusal is recorded, like every other denial the gateway produces.
      const logged = stub.calls.find((c) => c.fn === "record_api_request");
      assert.equal(logged?.body.p_status_code, 410);
      assert.equal(logged?.body.p_error_code, "api_version_gone");
      assert.equal(logged?.body.p_result, "failure");
    } finally {
      stub.restore();
    }
  });

  /**
   * The gate runs BEFORE authentication on purpose: whether a caller's key is valid is irrelevant
   * to an endpoint that no longer exists, and answering 410 only to holders of good keys would
   * leave everyone else guessing. This asserts that ordering directly — a sunset version must not
   * even reach the auth RPC.
   */
  test("a gone version short-circuits before authentication is attempted at all", async () => {
    const stub = installRpcFetchStub({
      evaluate_api_version_request: { data: [{ decision: "gone", status: "sunset", sunset_at: "2020-01-01T00:00:00.000Z" }] },
      authenticate_and_authorize_api_request: { data: okAuthRow() },
    });
    try {
      await GET(new Request("http://localhost/api/v1/status", BEARER));
      assert.equal(stub.calls.some((c) => c.fn === "authenticate_and_authorize_api_request"), false);
    } finally {
      stub.restore();
    }
  });

  test("a deprecated version is still SERVED, carrying RFC 8594 Deprecation and Sunset headers", async () => {
    const stub = installRpcFetchStub({
      ...STATUS_BODY_HANDLERS,
      evaluate_api_version_request: { data: [{ decision: "deprecated", status: "sunset", sunset_at: "2027-01-01T00:00:00.000Z" }] },
      authenticate_and_authorize_api_request: { data: okAuthRow() },
    });
    try {
      const response = await GET(new Request("http://localhost/api/v1/status", BEARER));
      // Deprecated means "still works, and here is your warning" — not an error. A gate that
      // refused here would turn the announcement into the outage it exists to prevent.
      assert.equal(response.status, 200);
      assert.equal(response.headers.get("deprecation"), "true");
      assert.equal(response.headers.get("sunset"), "Fri, 01 Jan 2027 00:00:00 GMT");
    } finally {
      stub.restore();
    }
  });

  test("an active version is served with no deprecation signal", async () => {
    const stub = installRpcFetchStub({
      ...STATUS_BODY_HANDLERS,
      evaluate_api_version_request: { data: [{ decision: "ok", status: "active", sunset_at: null }] },
      authenticate_and_authorize_api_request: { data: okAuthRow() },
    });
    try {
      const response = await GET(new Request("http://localhost/api/v1/status", BEARER));
      assert.equal(response.status, 200);
      assert.equal(response.headers.get("deprecation"), null);
      assert.equal(response.headers.get("sunset"), null);
    } finally {
      stub.restore();
    }
  });

  /**
   * The failure direction, pinned. `410 Gone` means PERMANENTLY gone; emitting it because the
   * registry read failed would tell every integrator the endpoint had been withdrawn, and
   * well-behaved clients would stop calling — a transient database error becoming a sticky,
   * self-inflicted outage across every integration at once. Serving costs nothing real, because
   * authentication reads the same database and will fail honestly on its own.
   */
  test("an unreadable registry serves the request rather than claiming permanent removal", async () => {
    const stub = installRpcFetchStub({
      ...STATUS_BODY_HANDLERS,
      evaluate_api_version_request: { status: 500, error: { message: "connection reset" } },
      authenticate_and_authorize_api_request: { data: okAuthRow() },
    });
    try {
      const response = await GET(new Request("http://localhost/api/v1/status", BEARER));
      assert.notEqual(response.status, 410);
      assert.equal(response.headers.get("deprecation"), null);
    } finally {
      stub.restore();
    }
  });
});
