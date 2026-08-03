import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  startDriverMobileSession,
  revokeDriverMobileSession,
  ingestDriverMobileReport,
  DriverMobileTrackingMutationError,
  type DriverMobileTrackingMutationRpcClient,
} from "./driver-mobile-tracking.ts";

const SLTS_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: DriverMobileTrackingMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as DriverMobileTrackingMutationRpcClient;
  return { client, calls };
}

describe("startDriverMobileSession", () => {
  test("calls start_driver_mobile_session with snake_case args and returns the raw token", async () => {
    const { client, calls } = fakeRpcClient({
      data: [{ driver_mobile_session_id: "323e4567-e89b-12d3-a456-426614174000", raw_token: "dmt_deadbeef", expires_at: "2026-08-04T00:00:00.000Z" }],
      error: null,
    });
    const result = await startDriverMobileSession(client, { shipmentLegTrackingSessionId: SLTS_ID, validityHours: 24, actorAuthUserId: ACTOR_ID, actorLabel: "admin" });
    assert.equal(result.rawToken, "dmt_deadbeef");
    assert.equal(calls[0]?.fn, "start_driver_mobile_session");
    assert.equal(calls[0]?.args.p_validity_hours, 24);
  });

  test("classifies an insufficient_authority error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks OPS:Edit" } });
    await assert.rejects(
      () => startDriverMobileSession(client, { shipmentLegTrackingSessionId: SLTS_ID, validityHours: 24, actorAuthUserId: ACTOR_ID, actorLabel: "viewer" }),
      (error: unknown) => error instanceof DriverMobileTrackingMutationError && error.code === "insufficient_authority",
    );
  });
});

describe("revokeDriverMobileSession", () => {
  test("calls revoke_driver_mobile_session with snake_case args", async () => {
    const { client, calls } = fakeRpcClient({
      data: {
        id: "323e4567-e89b-12d3-a456-426614174000",
        tenant_id: "223e4567-e89b-12d3-a456-426614174000",
        shipment_leg_tracking_session_id: SLTS_ID,
        status: "revoked",
        issued_at: "2026-08-03T00:00:00.000Z",
        expires_at: "2026-08-04T00:00:00.000Z",
        last_seen_at: null,
        revoked_at: "2026-08-03T01:00:00.000Z",
        revoked_reason: "lost phone",
        created_by: "admin",
        created_at: "2026-08-03T00:00:00.000Z",
      },
      error: null,
    });
    const session = await revokeDriverMobileSession(client, { shipmentLegTrackingSessionId: SLTS_ID, reason: "lost phone", actorAuthUserId: ACTOR_ID, actorLabel: "admin" });
    assert.equal(session.status, "revoked");
    assert.equal(calls[0]?.fn, "revoke_driver_mobile_session");
    assert.equal(calls[0]?.args.p_reason, "lost phone");
  });
});

describe("ingestDriverMobileReport", () => {
  test("returns an invalid ingestStatus without throwing", async () => {
    const { client } = fakeRpcClient({ data: [{ ingest_status: "invalid", report_id: null, session_ended: false }], error: null });
    const result = await ingestDriverMobileReport(client, { rawToken: "bogus", clientKey: "client-1", reportType: "heartbeat", eventAt: "2026-08-03T00:00:00.000Z" });
    assert.equal(result.ingestStatus, "invalid");
  });

  test("returns a rate_limited ingestStatus without throwing", async () => {
    const { client } = fakeRpcClient({ data: [{ ingest_status: "rate_limited", report_id: null, session_ended: false }], error: null });
    const result = await ingestDriverMobileReport(client, { rawToken: "bogus", clientKey: "client-1", reportType: "heartbeat", eventAt: "2026-08-03T00:00:00.000Z" });
    assert.equal(result.ingestStatus, "rate_limited");
  });

  test("passes snake_case args including the GeoJSON location", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ingest_status: "ok", report_id: "723e4567-e89b-12d3-a456-426614174000", session_ended: false }], error: null });
    const result = await ingestDriverMobileReport(client, {
      rawToken: "dmt_abc",
      clientKey: "client-1",
      reportType: "location",
      eventAt: "2026-08-03T00:00:00.000Z",
      location: { type: "Point", coordinates: [107.6191, -6.9175] },
      accuracyMeters: 12.5,
      batteryPercent: 83,
    });
    assert.equal(result.ingestStatus, "ok");
    assert.deepEqual(calls[0]?.args.p_location, { type: "Point", coordinates: [107.6191, -6.9175] });
    assert.equal(calls[0]?.args.p_accuracy_meters, 12.5);
  });

  test("throws only on a genuine transport error, not a business-logic invalid outcome", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "connection reset" } });
    await assert.rejects(
      () => ingestDriverMobileReport(client, { rawToken: "dmt_abc", clientKey: "client-1", reportType: "heartbeat", eventAt: "2026-08-03T00:00:00.000Z" }),
      DriverMobileTrackingMutationError,
    );
  });
});
