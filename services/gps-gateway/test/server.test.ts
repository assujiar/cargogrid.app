import { test } from "node:test";
import assert from "node:assert/strict";
import { connect } from "node:net";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { GpsGatewayServer, type GpsGatewayServerOptions } from "../src/server.ts";
import { DurableTelemetryBuffer } from "../src/buffer.ts";
import { encodeAvlDataPacket } from "../src/codec8e.ts";
import type { GpsGatewayIngestClientLike, HandshakeResult, IngestBatchResult, GatewayIngestReport } from "../src/ingestClient.ts";

const TEST_IMEI = "861112030001234";
const TEST_DEVICE_ID = "723e4567-e89b-12d3-a456-426614174003";
const TEST_TENANT_ID = "723e4567-e89b-12d3-a456-426614174002";

function imeiHandshakeBytes(imei: string): Buffer {
  return Buffer.concat([Buffer.from([0x00, imei.length]), Buffer.from(imei, "ascii")]);
}

function fakeIngestClient(overrides: Partial<GpsGatewayIngestClientLike> = {}): {
  client: GpsGatewayIngestClientLike;
  ingestedBatches: { deviceId: string; reports: GatewayIngestReport[] }[];
} {
  const ingestedBatches: { deviceId: string; reports: GatewayIngestReport[] }[] = [];
  const client: GpsGatewayIngestClientLike = {
    resolveHandshake: async (imei: string): Promise<HandshakeResult> => {
      if (imei === TEST_IMEI) {
        return { accepted: true, deviceId: TEST_DEVICE_ID, tenantId: TEST_TENANT_ID, rejectionReason: null };
      }
      return { accepted: false, deviceId: null, tenantId: null, rejectionReason: "imei_not_registered" };
    },
    ingestBatch: async (deviceId: string, reports: GatewayIngestReport[]): Promise<IngestBatchResult> => {
      ingestedBatches.push({ deviceId, reports });
      return { deviceId, tenantId: TEST_TENANT_ID, acceptedCount: reports.length, deviceStatus: "active" };
    },
    ...overrides,
  };
  return { client, ingestedBatches };
}

async function withServer<T>(
  client: GpsGatewayIngestClientLike,
  fn: (server: GpsGatewayServer, port: number, bufferFilePath: string) => Promise<T>,
  serverOptions: Partial<Omit<GpsGatewayServerOptions, "ingestClient" | "buffer" | "gatewayInstanceLabel">> = {},
): Promise<T> {
  const dir = await mkdtemp(join(tmpdir(), "gps-gateway-test-"));
  const bufferFilePath = join(dir, "buffer.jsonl");
  const buffer = new DurableTelemetryBuffer(bufferFilePath);
  const server = new GpsGatewayServer({ ingestClient: client, buffer, gatewayInstanceLabel: "test-gateway", ...serverOptions });
  await server.listen(0, "127.0.0.1");
  const port = server.boundPort;
  try {
    return await fn(server, port, bufferFilePath);
  } finally {
    await server.close();
    await rm(dir, { recursive: true, force: true });
  }
}

test("a device presenting a known IMEI is accepted (0x01), then a real AVL packet is ACKed with the accepted record count", async () => {
  const { client, ingestedBatches } = fakeIngestClient();
  await withServer(client, async (_server, port) => {
    const socket = connect(port, "127.0.0.1");
    await new Promise<void>((resolve) => socket.once("connect", resolve));

    const handshakeAck = new Promise<Buffer>((resolve) => socket.once("data", resolve));
    socket.write(imeiHandshakeBytes(TEST_IMEI));
    assert.deepEqual(await handshakeAck, Buffer.from([0x01]));

    const avlAck = new Promise<Buffer>((resolve) => socket.once("data", resolve));
    const packet = encodeAvlDataPacket([
      { timestampMs: 1_700_000_000_000n, priority: 1, longitude: 106.8, latitude: -6.2, altitudeMeters: 10, angleDegrees: 90, satellites: 8, speedKmh: 40 },
    ]);
    socket.write(packet);
    assert.deepEqual(await avlAck, Buffer.from([0x00, 0x00, 0x00, 0x01]));

    assert.equal(ingestedBatches.length, 1);
    assert.equal(ingestedBatches[0]?.deviceId, TEST_DEVICE_ID);
    assert.equal(ingestedBatches[0]?.reports[0]?.reportType, "location");

    socket.destroy();
  });
});

test("an unrecognized IMEI is rejected (0x00) and the connection is closed", async () => {
  const { client } = fakeIngestClient();
  await withServer(client, async (_server, port) => {
    const socket = connect(port, "127.0.0.1");
    await new Promise<void>((resolve) => socket.once("connect", resolve));

    const rejectByte = new Promise<Buffer>((resolve) => socket.once("data", resolve));
    const closed = new Promise<void>((resolve) => socket.once("close", resolve));
    socket.write(imeiHandshakeBytes("999999999999999"));
    assert.deepEqual(await rejectByte, Buffer.from([0x00]));
    await closed;
  });
});

test("a live ingest failure durably buffers the batch instead of dropping it, and still ACKs the device", async () => {
  const { client } = fakeIngestClient({
    ingestBatch: async () => {
      throw new Error("supabase_unreachable");
    },
  });
  await withServer(client, async (_server, port, bufferFilePath) => {
    const socket = connect(port, "127.0.0.1");
    await new Promise<void>((resolve) => socket.once("connect", resolve));

    const handshakeAck = new Promise<Buffer>((resolve) => socket.once("data", resolve));
    socket.write(imeiHandshakeBytes(TEST_IMEI));
    await handshakeAck;

    const avlAck = new Promise<Buffer>((resolve) => socket.once("data", resolve));
    const packet = encodeAvlDataPacket([
      { timestampMs: 1n, priority: 0, longitude: 1, latitude: 1, altitudeMeters: 0, angleDegrees: 0, satellites: 1, speedKmh: 0 },
    ]);
    socket.write(packet);
    assert.deepEqual(await avlAck, Buffer.from([0x00, 0x00, 0x00, 0x01]));

    const buffer = new DurableTelemetryBuffer(bufferFilePath);
    assert.equal(await buffer.pendingCount(), 1);

    socket.destroy();
  });
});

test("a malformed AVL packet (bad preamble) closes the connection without an ACK", async () => {
  const { client } = fakeIngestClient();
  await withServer(client, async (_server, port) => {
    const socket = connect(port, "127.0.0.1");
    await new Promise<void>((resolve) => socket.once("connect", resolve));

    const handshakeAck = new Promise<Buffer>((resolve) => socket.once("data", resolve));
    socket.write(imeiHandshakeBytes(TEST_IMEI));
    await handshakeAck;

    const closed = new Promise<void>((resolve) => socket.once("close", resolve));
    const badPacket = Buffer.concat([Buffer.from([0x01, 0x00, 0x00, 0x00]), Buffer.alloc(8)]);
    socket.write(badPacket);
    await closed;
  });
});

test("two AVL packets sent back-to-back in the same TCP chunk are both decoded and ACKed in order", async () => {
  const { client, ingestedBatches } = fakeIngestClient();
  await withServer(client, async (_server, port) => {
    const socket = connect(port, "127.0.0.1");
    await new Promise<void>((resolve) => socket.once("connect", resolve));

    const handshakeAck = new Promise<Buffer>((resolve) => socket.once("data", resolve));
    socket.write(imeiHandshakeBytes(TEST_IMEI));
    await handshakeAck;

    const packetA = encodeAvlDataPacket([{ timestampMs: 1n, priority: 0, longitude: 1, latitude: 1, altitudeMeters: 0, angleDegrees: 0, satellites: 1, speedKmh: 0 }]);
    const packetB = encodeAvlDataPacket([
      { timestampMs: 2n, priority: 0, longitude: 2, latitude: 2, altitudeMeters: 0, angleDegrees: 0, satellites: 1, speedKmh: 0 },
      { timestampMs: 3n, priority: 0, longitude: 3, latitude: 3, altitudeMeters: 0, angleDegrees: 0, satellites: 1, speedKmh: 0 },
    ]);

    const acks: Buffer[] = [];
    const allAcksReceived = new Promise<void>((resolve) => {
      socket.on("data", (chunk: Buffer) => {
        acks.push(chunk);
        if (acks.length === 2) resolve();
      });
    });
    socket.write(Buffer.concat([packetA, packetB]));
    await allAcksReceived;

    assert.deepEqual(acks[0], Buffer.from([0x00, 0x00, 0x00, 0x01]));
    assert.deepEqual(acks[1], Buffer.from([0x00, 0x00, 0x00, 0x02]));
    assert.equal(ingestedBatches.length, 2);
    assert.equal(ingestedBatches[0]?.reports.length, 1);
    assert.equal(ingestedBatches[1]?.reports.length, 2);

    socket.destroy();
  });
});

// ATW-246 finding 2 (concurrent-connection impersonation): two concurrent raw TCP
// connections presenting the identical IMEI previously both completed a full handshake --
// no exclusivity check existed. The gateway now tracks in-flight IMEI -> connection state
// in-process and rejects a second concurrent handshake for an already-open IMEI.
test("ATW-246 finding 2: a second concurrent handshake for an IMEI that already has an open connection is rejected (0x00), while the first connection stays open and fully functional", async () => {
  const { client, ingestedBatches } = fakeIngestClient();
  await withServer(client, async (_server, port) => {
    const socket1 = connect(port, "127.0.0.1");
    await new Promise<void>((resolve) => socket1.once("connect", resolve));
    const ack1 = new Promise<Buffer>((resolve) => socket1.once("data", resolve));
    socket1.write(imeiHandshakeBytes(TEST_IMEI));
    assert.deepEqual(await ack1, Buffer.from([0x01]));

    // Second, concurrent connection presenting the SAME IMEI while the first is still open.
    const socket2 = connect(port, "127.0.0.1");
    await new Promise<void>((resolve) => socket2.once("connect", resolve));
    const ack2 = new Promise<Buffer>((resolve) => socket2.once("data", resolve));
    const socket2Closed = new Promise<void>((resolve) => socket2.once("close", resolve));
    socket2.write(imeiHandshakeBytes(TEST_IMEI));
    assert.deepEqual(await ack2, Buffer.from([0x00]));
    await socket2Closed;

    // The first, legitimate connection is completely unaffected by the second connection's
    // rejection -- still open, still able to ingest a real AVL packet.
    const avlAck = new Promise<Buffer>((resolve) => socket1.once("data", resolve));
    const packet = encodeAvlDataPacket([
      { timestampMs: 1_700_000_000_000n, priority: 1, longitude: 106.8, latitude: -6.2, altitudeMeters: 10, angleDegrees: 90, satellites: 8, speedKmh: 40 },
    ]);
    socket1.write(packet);
    assert.deepEqual(await avlAck, Buffer.from([0x00, 0x00, 0x00, 0x01]));
    assert.equal(ingestedBatches.length, 1);

    socket1.destroy();
  });
});

test("ATW-246 finding 2: a DIFFERENT IMEI is unaffected by another IMEI's already-open connection (the exclusivity check is per-IMEI, not global)", async () => {
  const { client } = fakeIngestClient({
    resolveHandshake: async (imei: string): Promise<HandshakeResult> => ({
      accepted: true,
      deviceId: imei === TEST_IMEI ? TEST_DEVICE_ID : "723e4567-e89b-12d3-a456-426614174099",
      tenantId: TEST_TENANT_ID,
      rejectionReason: null,
    }),
  });
  await withServer(client, async (_server, port) => {
    const socket1 = connect(port, "127.0.0.1");
    await new Promise<void>((resolve) => socket1.once("connect", resolve));
    const ack1 = new Promise<Buffer>((resolve) => socket1.once("data", resolve));
    socket1.write(imeiHandshakeBytes(TEST_IMEI));
    assert.deepEqual(await ack1, Buffer.from([0x01]));

    const socket2 = connect(port, "127.0.0.1");
    await new Promise<void>((resolve) => socket2.once("connect", resolve));
    const ack2 = new Promise<Buffer>((resolve) => socket2.once("data", resolve));
    socket2.write(imeiHandshakeBytes("861112030009999"));
    assert.deepEqual(await ack2, Buffer.from([0x01]));

    socket1.destroy();
    socket2.destroy();
  });
});

test("ATW-246 finding 2: once the first connection for an IMEI fully closes, a new connection for that same IMEI is accepted again (the claim is released on close, never stuck forever)", async () => {
  const { client } = fakeIngestClient();
  await withServer(client, async (_server, port) => {
    const socket1 = connect(port, "127.0.0.1");
    await new Promise<void>((resolve) => socket1.once("connect", resolve));
    const ack1 = new Promise<Buffer>((resolve) => socket1.once("data", resolve));
    socket1.write(imeiHandshakeBytes(TEST_IMEI));
    assert.deepEqual(await ack1, Buffer.from([0x01]));
    socket1.destroy();

    // The server-side release of this IMEI happens on the SERVER's own socket 'close'
    // event, which is not perfectly synchronized with this client-side socket1 finishing
    // its own teardown -- poll with a short bounded retry (real TCP connections each
    // time, never a fake/skipped assertion) instead of assuming instantaneous
    // cross-socket ordering.
    const deadline = Date.now() + 2_000;
    let accepted = false;
    while (Date.now() < deadline && !accepted) {
      const socket2 = connect(port, "127.0.0.1");
      await new Promise<void>((resolve) => socket2.once("connect", resolve));
      const ack2 = new Promise<Buffer>((resolve) => socket2.once("data", resolve));
      socket2.write(imeiHandshakeBytes(TEST_IMEI));
      const response = await ack2;
      if (response.equals(Buffer.from([0x01]))) {
        accepted = true;
        socket2.destroy();
      } else {
        socket2.destroy();
        await new Promise((resolve) => setTimeout(resolve, 20));
      }
    }
    assert.equal(accepted, true, "expected the IMEI to become available again once the first connection fully closed");
  });
});

// ATW-246 finding 6 (TCP socket exhaustion): no idle-read timeout, no maxConnections cap.
test("ATW-246 finding 6: a connection that sends nothing is destroyed by the server after idleTimeoutMs, never left open indefinitely", async () => {
  const { client } = fakeIngestClient();
  await withServer(
    client,
    async (_server, port) => {
      const socket = connect(port, "127.0.0.1");
      await new Promise<void>((resolve) => socket.once("connect", resolve));

      const closed = new Promise<void>((resolve) => socket.once("close", resolve));
      // Deliberately never writes anything on this connection -- it must be closed by
      // the server's own idle-read timeout, not by anything the client does.
      const start = Date.now();
      await closed;
      const elapsedMs = Date.now() - start;
      // A generous upper bound (well under the 30s+ a hung-forever connection would
      // imply) -- proves the server, not a test-level fallback, closed the socket.
      assert.ok(elapsedMs < 5_000, `expected the idle connection to close quickly after idleTimeoutMs, took ${elapsedMs}ms`);
    },
    { idleTimeoutMs: 100 },
  );
});

test("ATW-246 finding 6: a connection beyond maxConnections is destroyed by the server before any handshake exchange happens, while a connection within the cap works normally", async () => {
  const { client } = fakeIngestClient();
  await withServer(
    client,
    async (_server, port) => {
      const socket1 = connect(port, "127.0.0.1");
      await new Promise<void>((resolve) => socket1.once("connect", resolve));

      const socket2 = connect(port, "127.0.0.1");
      const socket2Closed = new Promise<void>((resolve) => socket2.once("close", resolve));
      socket2.on("error", () => {
        // A connection destroyed server-side beyond maxConnections may also surface as
        // an ECONNRESET-shaped error on the client end -- irrelevant here, we only
        // assert that it closes.
      });
      await socket2Closed;

      // socket1 (within the cap) remains completely unaffected.
      const ack1 = new Promise<Buffer>((resolve) => socket1.once("data", resolve));
      socket1.write(imeiHandshakeBytes(TEST_IMEI));
      assert.deepEqual(await ack1, Buffer.from([0x01]));

      socket1.destroy();
    },
    { maxConnections: 1 },
  );
});
