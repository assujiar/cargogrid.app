/**
 * ATW-026 (Prompt 245, "Advanced TMS/WMS Integrated Verification") -- Mandatory
 * tracking E2E #2: Direct Fleet GPS. READ-ONLY VERIFICATION PROOF, NOT A NEW
 * CAPABILITY -- adds no schema, no new RPC, no new business rule. It composes
 * already-VERIFIED, unmodified pieces from two separate ATW-226 checkpoints
 * that were never previously exercised together end to end:
 *
 *   - services/gps-gateway/src/server.ts (GpsGatewayServer) and
 *     services/gps-gateway/src/codec8e.ts (the real Teltonika Codec 8 Extended
 *     byte-level simulator/encoder, ATW-226D) -- imported verbatim, never
 *     re-implemented, per this task's own explicit instruction not to rebuild a
 *     protocol encoder.
 *   - app.resolve_gps_device_for_handshake / app.ingest_direct_device_telemetry_
 *     batch (the real, already-VERIFIED Postgres RPCs those modules call in
 *     production), reached here through a REAL disposable Postgres database via
 *     the SAME shared scripts/db-tests/lib/setup-disposable-db.sh helper every
 *     db-test/load-test in this repository already uses.
 *
 * The ONE genuinely new piece is PsqlBackedGpsIngestClient below: a
 * GpsGatewayIngestClientLike implementation that calls those two real RPCs via
 * `psql` (mirroring this repository's own established convention -- every
 * existing db-test/load-test script already shells out to psql; no new `pg`
 * npm dependency is introduced). This closes the exact, disclosed gap
 * scripts/load-tests/gps-telemetry-load.ts's own header names: "the ingest
 * CLIENT is replaced with a fast, in-memory fake for this load run... since a
 * live Supabase/PostgREST endpoint is not available in this sandbox (ADR-0010)"
 * -- and which docs/runtime/KNOWN_ISSUES.md ISS-2026-019 lists as an open gap
 * ("Canonical projection measured against a live database... remain unbuilt").
 * This script is the first real, executed proof of IMEI handshake -> Codec 8
 * Extended parsing -> ACK -> REAL canonical Postgres projection (app.
 * canonical_telemetry_events / app.vehicle_current_positions), all over real
 * node:net TCP sockets, against a real, freshly-migrated Postgres database.
 *
 * External-evidence policy: no physical Teltonika hardware exists in this
 * environment -- this remains DEFERRED_EXTERNAL_HARDWARE_EVIDENCE exactly as
 * ATW-226D's own build log already discloses. A real net.Socket client
 * speaking the exact wire protocol against the real, unmodified server code is
 * this checkpoint's own repository-controlled evidence, per 245_*.md section 8's
 * "External-evidence policy" (protocol simulators / recorded frames allowance).
 *
 * Run: node --experimental-strip-types scripts/verification/atw-026-direct-fleet-gps-canonical-projection.ts
 * Requires a reachable Postgres server (DATABASE_ADMIN_URL, defaults to the same
 * postgres/postgres/127.0.0.1:5432 convention scripts/db-tests/run.sh uses).
 * Creates and drops its own disposable database
 * (ATW026_GATEWAY_DB_NAME, default cargogrid_atw026_gateway_verify) --
 * independent of, and never touching, the shared cargogrid_db_test/
 * cargogrid_load_test databases scripts/db-tests/run.sh and
 * scripts/load-tests/run.sh use, so this script is safe to run alongside them.
 */

import { execFileSync } from "node:child_process";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { GpsGatewayServer } from "../../services/gps-gateway/src/server.ts";
import { DurableTelemetryBuffer } from "../../services/gps-gateway/src/buffer.ts";
import { encodeAvlDataPacket } from "../../services/gps-gateway/src/codec8e.ts";
import type {
  GpsGatewayIngestClientLike,
  HandshakeResult,
  IngestBatchResult,
  GatewayIngestReport,
} from "../../services/gps-gateway/src/ingestClient.ts";
import { connect, type Socket } from "node:net";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, "..", "..");
const DATABASE_ADMIN_URL = process.env.DATABASE_ADMIN_URL ?? "postgresql://postgres:postgres@127.0.0.1:5432/postgres";
const TEST_DB_NAME = process.env.ATW026_GATEWAY_DB_NAME ?? "cargogrid_atw026_gateway_verify";
const FIXTURE_IMEI = "868712349912345";

let failures = 0;
function check(label: string, condition: boolean, detail?: unknown): void {
  if (condition) {
    console.log(`  PASS -- ${label}`);
  } else {
    failures += 1;
    console.log(`  FAIL -- ${label}${detail !== undefined ? ` (${JSON.stringify(detail)})` : ""}`);
  }
}

// ---------------------------------------------------------------------------
// Disposable-database setup, reusing the SAME shared bash helper every
// db-test/load-test script already sources -- never duplicated here.
// ---------------------------------------------------------------------------
function setupDisposableDb(): string {
  const script = [
    "set -euo pipefail",
    `cd ${JSON.stringify(REPO_ROOT)}`,
    "source scripts/db-tests/lib/setup-disposable-db.sh",
    `cargogrid_setup_disposable_db ${JSON.stringify(DATABASE_ADMIN_URL)} ${JSON.stringify(TEST_DB_NAME)} ${JSON.stringify(REPO_ROOT)} ${JSON.stringify(join(REPO_ROOT, "scripts/db-tests/fixtures"))} 1>&2`,
    'echo "$CARGOGRID_TEST_DB_URL"',
  ].join("\n");
  const out = execFileSync("bash", ["-c", script], { encoding: "utf8", stdio: ["ignore", "pipe", "inherit"] });
  const lines = out.trim().split("\n");
  const dbUrl = lines[lines.length - 1];
  if (!dbUrl || !dbUrl.startsWith("postgresql://")) {
    throw new Error(`setupDisposableDb: could not resolve CARGOGRID_TEST_DB_URL from setup output: ${out}`);
  }
  return dbUrl;
}

function dropDisposableDb(): void {
  execFileSync("psql", [DATABASE_ADMIN_URL, "-v", "ON_ERROR_STOP=1", "-c", `DROP DATABASE IF EXISTS ${TEST_DB_NAME};`], {
    encoding: "utf8",
  });
}

function psqlScalar(dbUrl: string, sql: string): string {
  return execFileSync("psql", [dbUrl, "-v", "ON_ERROR_STOP=1", "-Atqc", sql], { encoding: "utf8" }).trim();
}

function psqlCommand(dbUrl: string, sql: string): string {
  return execFileSync("psql", [dbUrl, "-v", "ON_ERROR_STOP=1", "-c", sql], { encoding: "utf8" });
}

/** Doubles embedded single quotes -- the same escaping convention every bash-driven db-test/load-test SQL fixture in this repository already relies on (values here are entirely script-generated, never external/user input). */
function sqlStr(value: string): string {
  return `'${value.replace(/'/g, "''")}'`;
}

// ---------------------------------------------------------------------------
// Fixture: one tenant, one vehicle (all tracking eligibility on), one GPS
// device installed and assigned to that vehicle, one OPS:Edit-scoped API key
// -- the minimal real state app.resolve_gps_device_for_handshake / app.
// ingest_direct_device_telemetry_batch require. No shipment/commercial
// pipeline needed -- ATW-226D's own vehicle resolution (app.resolve_vehicle_
// for_gps_device) is keyed by app.device_vehicle_assignments alone, confirmed
// by direct inspection of that function's own body.
// ---------------------------------------------------------------------------
interface Fixture {
  tenantId: string;
  vehicleMasterId: string;
  deviceId: string;
  rawApiKey: string;
}

function createFixture(dbUrl: string): Fixture {
  const adminActor = "00000000-0000-0000-0000-000000997001";
  const supremeActor = "00000000-0000-0000-0000-000000997003";
  const setupSql = `
do $$
declare
  v_tenant uuid;
  v_edit_role uuid;
  v_edit_draft app.role_versions;
  v_vehicle app.vehicle_operational_profiles;
  v_device app.gps_devices;
  v_key record;
begin
  insert into auth.users (id, email) values
    ('${adminActor}', 'admin@atw026gateway.test'),
    ('${supremeActor}', 'supreme@atw026gateway.test');
  perform app.grant_principal_membership('${supremeActor}', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('atw026gateway', 'ATW026 Gateway Verify Co', 'idem-atw026gateway', 'tester');
  v_tenant := (select id from app.tenants where slug = 'atw026gateway');
  perform app.transition_tenant_status(v_tenant, 'active', 'setup', 'tester');
  perform app.invite_user(v_tenant, '${adminActor}', 'admin@atw026gateway.test', 'Gateway Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@atw026gateway.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('${adminActor}', 'tenant_admin', v_tenant, null, 'tester');

  v_edit_role := (app.create_role(v_tenant, 'Gateway Editor', 'OPS full', 'tester')).id;
  v_edit_draft := app.create_role_version(v_edit_role, 'tester');
  perform app.set_role_version_permissions(
    v_edit_draft.id,
    array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Assign')),
    'tester'
  );
  perform app.publish_role_version(v_edit_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant, (select id from app.role_versions where role_id = v_edit_role and status = 'published'), '${adminActor}', '${supremeActor}', 'tester');

  select * into v_vehicle from app.register_vehicle_operational_profile(v_tenant, 'VEH-ATW026-GW', 'ATW026 Gateway Truck', 'owned', 2000, 20, '${adminActor}', 'admin');
  select * into v_vehicle from app.set_vehicle_tracking_eligibility(v_vehicle.id, true, true, true, v_vehicle.record_version, '${adminActor}', 'admin');

  select * into v_device from app.register_gps_device(v_tenant, '${FIXTURE_IMEI}', 'Teltonika FMC920', 'cargogrid', '${adminActor}', 'admin');
  select * into v_device from app.transition_gps_device_status(v_device.id, 'assigned', v_device.record_version, '${adminActor}', 'admin');
  select * into v_device from app.transition_gps_device_status(v_device.id, 'installed', v_device.record_version, '${adminActor}', 'admin');
  perform app.assign_device_to_vehicle(v_device.id, v_vehicle.id, 'atw026 gateway verification fixture', '${adminActor}', 'admin');

  select * into v_key from app.create_api_key(v_tenant, 'ATW026 Gateway Verify Key', '["OPS:Edit"]'::jsonb, null, null, '${adminActor}', 'admin');

  create table if not exists public.atw026_gateway_fixture (key text primary key, value text not null);
  insert into public.atw026_gateway_fixture (key, value) values
    ('tenant_id', v_tenant::text),
    ('vehicle_master_id', v_vehicle.vehicle_master_id::text),
    ('device_id', v_device.id::text),
    ('raw_api_key', v_key.raw_key);
end $$;
`;
  psqlCommand(dbUrl, setupSql);
  return {
    tenantId: psqlScalar(dbUrl, "select value from public.atw026_gateway_fixture where key = 'tenant_id';"),
    vehicleMasterId: psqlScalar(dbUrl, "select value from public.atw026_gateway_fixture where key = 'vehicle_master_id';"),
    deviceId: psqlScalar(dbUrl, "select value from public.atw026_gateway_fixture where key = 'device_id';"),
    rawApiKey: psqlScalar(dbUrl, "select value from public.atw026_gateway_fixture where key = 'raw_api_key';"),
  };
}

// ---------------------------------------------------------------------------
// The one new piece: a REAL, Postgres-backed ingest client. Same wire shape
// GpsGatewayIngestClient (services/gps-gateway/src/ingestClient.ts) already
// uses -- calls the identical two RPCs, only the transport differs (psql
// against a real disposable database here, vs. supabase-js/PostgREST in
// production -- no live Supabase/PostgREST endpoint exists in this sandbox,
// ADR-0010, unchanged by this checkpoint).
// ---------------------------------------------------------------------------
class PsqlBackedGpsIngestClient implements GpsGatewayIngestClientLike {
  private readonly dbUrl: string;
  private readonly rawApiKey: string;
  private readonly gatewayInstanceLabel: string;

  // node --experimental-strip-types does not support TypeScript constructor
  // parameter properties (the identical, already-disclosed repository-wide
  // constraint services/gps-gateway/src/buffer.ts's own DurableTelemetryBuffer
  // works around the same way -- ATW-226D build log 4.1 finding 4).
  constructor(dbUrl: string, rawApiKey: string, gatewayInstanceLabel: string) {
    this.dbUrl = dbUrl;
    this.rawApiKey = rawApiKey;
    this.gatewayInstanceLabel = gatewayInstanceLabel;
  }

  async resolveHandshake(imei: string): Promise<HandshakeResult> {
    const sql = `select accepted, device_id, tenant_id, rejection_reason from app.resolve_gps_device_for_handshake(${sqlStr(this.rawApiKey)}, ${sqlStr(imei)}, ${sqlStr(this.gatewayInstanceLabel)});`;
    const row = psqlScalar(this.dbUrl, sql);
    const [accepted, deviceId, tenantId, rejectionReason] = row.split("|");
    return {
      accepted: accepted === "t",
      deviceId: deviceId || null,
      tenantId: tenantId || null,
      rejectionReason: rejectionReason || null,
    };
  }

  async ingestBatch(deviceId: string, reports: GatewayIngestReport[]): Promise<IngestBatchResult> {
    const reportsJson = JSON.stringify(
      reports.map((report) => ({
        report_type: report.reportType,
        event_at: report.eventAt,
        longitude: report.longitude,
        latitude: report.latitude,
        altitude_meters: report.altitudeMeters,
        heading_degrees: report.headingDegrees,
        speed_kmh: report.speedKmh,
        satellite_count: report.satelliteCount,
        raw_codec_id: report.rawCodecId,
        io_elements: report.ioElements,
      })),
    );
    const sql = `select device_id, tenant_id, accepted_count, device_status from app.ingest_direct_device_telemetry_batch(${sqlStr(this.rawApiKey)}, ${sqlStr(deviceId)}, ${sqlStr(reportsJson)}::jsonb, ${sqlStr(this.gatewayInstanceLabel)});`;
    const row = psqlScalar(this.dbUrl, sql);
    const [outDeviceId, outTenantId, acceptedCount, deviceStatus] = row.split("|");
    return {
      deviceId: outDeviceId!,
      tenantId: outTenantId!,
      acceptedCount: Number(acceptedCount),
      deviceStatus: deviceStatus!,
    };
  }
}

// ---------------------------------------------------------------------------
// Real TCP client helpers -- byte-identical technique to scripts/load-tests/
// gps-telemetry-load.ts's own already-proven simulator (reused, not re-derived).
// ---------------------------------------------------------------------------
function imeiHandshakeBytes(imei: string): Buffer {
  return Buffer.concat([Buffer.from([0x00, imei.length]), Buffer.from(imei, "ascii")]);
}

async function connectAndHandshake(port: number, imei: string): Promise<{ socket: Socket; accepted: boolean }> {
  const socket = connect(port, "127.0.0.1");
  await new Promise<void>((resolve, reject) => {
    socket.once("connect", resolve);
    socket.once("error", reject);
  });
  const handshakeAck = new Promise<Buffer>((resolve) => socket.once("data", resolve));
  socket.write(imeiHandshakeBytes(imei));
  const ack = await handshakeAck;
  return { socket, accepted: ack.length === 1 && ack[0] === 0x01 };
}

async function sendPacketAndAwaitAck(socket: Socket, packet: Buffer): Promise<{ ok: boolean; acceptedCount: number }> {
  return new Promise((resolve) => {
    const onData = (chunk: Buffer) => {
      socket.removeListener("data", onData);
      if (chunk.length !== 4) {
        resolve({ ok: false, acceptedCount: -1 });
        return;
      }
      resolve({ ok: true, acceptedCount: chunk.readUInt32BE(0) });
    };
    socket.on("data", onData);
    socket.write(packet);
  });
}

async function main(): Promise<void> {
  console.log("=== ATW-026 Mandatory Tracking E2E #2: Direct Fleet GPS (real sockets, real canonical Postgres projection) ===");

  console.log("\n### 1. Disposable database setup (shared lib, same convention as scripts/db-tests/run.sh) ###");
  const dbUrl = setupDisposableDb();
  console.log(`disposable database ready: ${dbUrl.replace(/:[^:@]+@/, ":***@")}`);

  console.log("\n### 2. Fixture: tenant, vehicle, GPS device (installed + assigned), OPS:Edit API key ###");
  const fixture = createFixture(dbUrl);
  console.log(`fixture ready: tenant_id=${fixture.tenantId} vehicle_master_id=${fixture.vehicleMasterId} device_id=${fixture.deviceId} imei=${FIXTURE_IMEI}`);

  const bufferDir = await mkdtemp(join(tmpdir(), "cargogrid-atw026-gateway-"));
  const buffer = new DurableTelemetryBuffer(join(bufferDir, "buffer.jsonl"));
  const ingestClient = new PsqlBackedGpsIngestClient(dbUrl, fixture.rawApiKey, "atw026-verification-gateway");
  const server = new GpsGatewayServer({ ingestClient, buffer, gatewayInstanceLabel: "atw026-verification-gateway", onLog: (line) => console.log(`  [gateway] ${line}`) });
  await server.listen(0, "127.0.0.1");
  const port = server.boundPort;
  console.log(`\n### 3. Real GpsGatewayServer (unmodified, ATW-226D) listening on 127.0.0.1:${port} ###`);

  try {
    console.log("\n### 4. Real IMEI handshake over a real TCP socket ###");
    const { socket, accepted } = await connectAndHandshake(port, FIXTURE_IMEI);
    check("IMEI handshake accepted for the real, installed, fixture device", accepted);

    console.log("\n### 5. Real Codec 8 Extended AVL data packet (1 location + 1 heartbeat record), real CRC-16, real ACK ###");
    const eventTimestampMs = BigInt(Date.now());
    const packet = encodeAvlDataPacket([
      {
        timestampMs: eventTimestampMs,
        priority: 1,
        longitude: 106.845599,
        latitude: -6.208763,
        altitudeMeters: 12,
        angleDegrees: 90,
        satellites: 9,
        speedKmh: 38,
      },
      {
        timestampMs: eventTimestampMs + 1000n,
        priority: 1,
        longitude: 0,
        latitude: 0,
        altitudeMeters: 0,
        angleDegrees: 0,
        satellites: 0,
        speedKmh: 0,
      },
    ]);
    const ackResult = await sendPacketAndAwaitAck(socket, packet);
    check("real AVL packet ACKed with acceptedCount=2 (1 location + 1 heartbeat, real CRC-16 validated by the real server)", ackResult.ok && ackResult.acceptedCount === 2, ackResult);
    socket.destroy();

    console.log("\n### 6. REAL canonical Postgres projection -- direct SQL against the actual disposable database (not a fake/in-memory client) ###");
    const rawReportCount = psqlScalar(dbUrl, `select count(*) from app.direct_device_telemetry_reports where device_id = ${sqlStr(fixture.deviceId)};`);
    check("2 raw direct_device_telemetry_reports rows stored (append-only raw log)", rawReportCount === "2", rawReportCount);

    const canonicalRow = psqlScalar(
      dbUrl,
      `select source_type, applied_to_current_position, rejection_reason from app.canonical_telemetry_events where vehicle_master_id = ${sqlStr(fixture.vehicleMasterId)} and rejection_reason is null;`,
    );
    const [canonicalSource, canonicalApplied] = canonicalRow.split("|");
    check("real canonical_telemetry_events row written via app.arbitrate_and_project_vehicle_position, source_type=direct_device, applied_to_current_position=true", canonicalSource === "direct_device" && canonicalApplied === "t", canonicalRow);

    const positionRow = psqlScalar(
      dbUrl,
      `select source_type, (location_geojson -> 'coordinates' ->> 0)::numeric, (location_geojson -> 'coordinates' ->> 1)::numeric from app.get_vehicle_current_position(${sqlStr(fixture.vehicleMasterId)});`,
    );
    const [positionSource, lon, lat] = positionRow.split("|");
    check(
      "app.vehicle_current_positions (the real canonical current-position projection) reflects the EXACT coordinates sent over the real socket -- source_type=direct_device",
      positionSource === "direct_device" && Math.abs(Number(lon) - 106.845599) < 0.00001 && Math.abs(Number(lat) - (-6.208763)) < 0.00001,
      positionRow,
    );

    const deviceStatusRow = psqlScalar(dbUrl, `select status, last_telemetry_at is not null from app.gps_devices where id = ${sqlStr(fixture.deviceId)};`);
    check("device auto-transitioned installed -> active on accepted telemetry, last_telemetry_at recorded", deviceStatusRow === "active|t", deviceStatusRow);

    console.log("\n### 7. Malformed packet rejected cleanly -- connection closed, no ACK, server keeps running (already proven in isolation by services/gps-gateway/test/server.test.ts; re-verified here against the REAL Postgres-backed ingest client, not a fake one) ###");
    const malformed = await connectAndHandshake(port, FIXTURE_IMEI);
    check("second connection also handshakes correctly (no stale per-IMEI state)", malformed.accepted);
    const closed = new Promise<void>((resolve) => malformed.socket.once("close", resolve));
    const badPacket = Buffer.concat([Buffer.from([0x01, 0x00, 0x00, 0x00]), Buffer.alloc(8)]);
    malformed.socket.write(badPacket);
    await closed;
    check("malformed packet closes the connection without crashing the server", true);

    console.log("\n### 8. Reconnect with the SAME IMEI (transient cellular drop simulation) -- a fresh AVL packet after reconnect still reaches the REAL canonical projection ###");
    const reconnected = await connectAndHandshake(port, FIXTURE_IMEI);
    check("reconnect handshake accepted", reconnected.accepted);
    const reconnectTimestampMs = BigInt(Date.now());
    const reconnectPacket = encodeAvlDataPacket([
      { timestampMs: reconnectTimestampMs, priority: 1, longitude: 106.9, latitude: -6.25, altitudeMeters: 15, angleDegrees: 45, satellites: 8, speedKmh: 42 },
    ]);
    const reconnectAck = await sendPacketAndAwaitAck(reconnected.socket, reconnectPacket);
    check("post-reconnect packet ACKed", reconnectAck.ok && reconnectAck.acceptedCount === 1, reconnectAck);
    reconnected.socket.destroy();
    const rawReportCountAfterReconnect = psqlScalar(dbUrl, `select count(*) from app.direct_device_telemetry_reports where device_id = ${sqlStr(fixture.deviceId)};`);
    check("raw report count now 3 (2 from the first packet + 1 from the post-reconnect packet -- the malformed packet was rejected before any record could be stored)", rawReportCountAfterReconnect === "3", rawReportCountAfterReconnect);

    console.log("\n### 9. Unknown IMEI is rejected at handshake, never silently accepted (a real, expected outcome -- random scanners/misconfigured devices routinely dial this port) ###");
    const unknown = await connectAndHandshake(port, "999999999999999");
    check("unknown IMEI handshake rejected", !unknown.accepted);
    unknown.socket.destroy();

    console.log(`\n### Server metrics (real, accumulated across this run): ${JSON.stringify(server.metrics)} ###`);
    check("packetsDecoded=2 (the two successfully-decoded AVL packets; the malformed one is tracked separately in packetsRejected, never reaches packetsDecoded)", server.metrics.packetsDecoded === 2, server.metrics);
    check("packetsRejected=1 (the one malformed packet)", server.metrics.packetsRejected === 1, server.metrics.packetsRejected);
    check("reportsIngestedLive=3 (2 first packet + 1 reconnect packet -- all real, live Postgres writes, zero buffered/fake)", server.metrics.reportsIngestedLive === 3, server.metrics.reportsIngestedLive);
  } finally {
    await server.close();
    await rm(bufferDir, { recursive: true, force: true });
    dropDisposableDb();
  }

  console.log(`\n=== RESULT: ${failures === 0 ? "PASS" : "FAIL"} (${failures} failing check(s)) ===`);
  console.log("DIRECT_FLEET_GPS_CANONICAL_PROJECTION_SCENARIO: " + (failures === 0 ? "PASS" : "FAIL"));
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((error) => {
  console.error("ATW-026 direct-fleet-gps-canonical-projection scenario crashed:", error);
  try {
    dropDisposableDb();
  } catch {
    // best-effort cleanup only
  }
  process.exit(1);
});
