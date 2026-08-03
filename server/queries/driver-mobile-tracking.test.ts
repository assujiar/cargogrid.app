import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getDriverMobileTrackingSession, listDriverMobilePositionReports, DriverMobileTrackingQueryError, type DriverMobileTrackingQueryClient } from "./driver-mobile-tracking.ts";

const SLTS_ID = "423e4567-e89b-12d3-a456-426614174000";
const SESSION_ID = "323e4567-e89b-12d3-a456-426614174000";
const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";

function fakeTableClient(response: { data: unknown; error: { message: string } | null }): DriverMobileTrackingQueryClient {
  return {
    from(table: string) {
      assert.equal(table, "driver_mobile_tracking_sessions");
      const chain = {
        select() {
          return chain;
        },
        eq() {
          return chain;
        },
        async maybeSingle() {
          return response;
        },
      };
      return chain;
    },
    rpc() {
      throw new Error("not used in this fake");
    },
  } as unknown as DriverMobileTrackingQueryClient;
}

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): { client: DriverMobileTrackingQueryClient; calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    from() {
      throw new Error("not used in this fake");
    },
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as DriverMobileTrackingQueryClient;
  return { client, calls };
}

describe("getDriverMobileTrackingSession", () => {
  test("returns null when no active token was ever issued", async () => {
    const client = fakeTableClient({ data: null, error: null });
    const session = await getDriverMobileTrackingSession(client, SLTS_ID);
    assert.equal(session, null);
  });

  test("parses an active session row", async () => {
    const client = fakeTableClient({
      data: {
        id: SESSION_ID,
        tenant_id: TENANT_ID,
        shipment_leg_tracking_session_id: SLTS_ID,
        status: "active",
        issued_at: "2026-08-03T00:00:00.000Z",
        expires_at: "2026-08-04T00:00:00.000Z",
        last_seen_at: null,
        revoked_at: null,
        revoked_reason: null,
        created_by: "admin",
        created_at: "2026-08-03T00:00:00.000Z",
      },
      error: null,
    });
    const session = await getDriverMobileTrackingSession(client, SLTS_ID);
    assert.ok(session);
    assert.equal(session?.status, "active");
  });

  test("throws on a query error", async () => {
    const client = fakeTableClient({ data: null, error: { message: "boom" } });
    await assert.rejects(() => getDriverMobileTrackingSession(client, SLTS_ID), DriverMobileTrackingQueryError);
  });
});

describe("listDriverMobilePositionReports", () => {
  test("maps rows via the get_driver_mobile_position_reports RPC", async () => {
    const { client, calls } = fakeRpcClient({
      data: [
        {
          id: "723e4567-e89b-12d3-a456-426614174000",
          tenant_id: TENANT_ID,
          driver_mobile_tracking_session_id: SESSION_ID,
          report_type: "heartbeat",
          event_at: "2026-08-03T00:00:00.000Z",
          received_at: "2026-08-03T00:00:00.000Z",
          location_geojson: null,
          accuracy_meters: null,
          battery_percent: 85,
          location_permission_granted: true,
          background_permission_granted: false,
          raw_payload: {},
          created_at: "2026-08-03T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const reports = await listDriverMobilePositionReports(client, SESSION_ID);
    assert.equal(reports.length, 1);
    assert.equal(calls[0]?.fn, "get_driver_mobile_position_reports");
    assert.equal(calls[0]?.args.p_driver_mobile_tracking_session_id, SESSION_ID);
  });
});
