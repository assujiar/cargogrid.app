/**
 * The raw TCP listener (226_GPS_TELEMATICS_INTEGRATION_PROMPT.md §14B) -- IMEI
 * handshake, then a stream of Codec 8 Extended AVL data packets, per connection.
 *
 * Per-connection protocol state machine: `awaiting_handshake` -> (accepted) ->
 * `awaiting_avl_data`. A rejected handshake (unknown/foreign IMEI, wrong-tenant, a
 * device not currently in an ingestible status) gets the single 0x00 reply byte and an
 * immediate socket close -- never left half-open. A malformed or oversized packet
 * (§14B: "malformed/oversized packet rejection") also closes the connection immediately,
 * without an ACK and without crashing the server process -- one bad device/connection
 * never takes down every other concurrent connection.
 *
 * A batch's own live ingest failure (Supabase unreachable, transient error) does not
 * fail the connection or withhold the ACK -- it is durably buffered instead
 * (src/buffer.ts) and the full record count is still ACKed, since durable local
 * persistence is this gateway's own real point of custody transfer: once a batch is on
 * disk, the physical device does not need to hold or retransmit it, and the buffer's own
 * background flush loop (src/index.ts) is what retries the write to Supabase.
 */

import { createServer, type Socket, type Server } from "node:net";
import {
  decodeImeiHandshake,
  encodeHandshakeResponse,
  decodeAvlDataPacket,
  encodeAckResponse,
  type DecodedAvlRecord,
  type Bytes,
} from "./codec8e.ts";
import type { GatewayIngestReport, GpsGatewayIngestClientLike } from "./ingestClient.ts";
import type { DurableTelemetryBuffer } from "./buffer.ts";

const MAX_BUFFERED_BYTES = 65_536;

export interface GpsGatewayServerMetrics {
  connectionsOpened: number;
  handshakesAccepted: number;
  handshakesRejected: number;
  packetsDecoded: number;
  packetsRejected: number;
  reportsIngestedLive: number;
  reportsBuffered: number;
}

type ConnectionState =
  | { phase: "awaiting_handshake" }
  | { phase: "awaiting_avl_data"; deviceId: string; imei: string };

function recordToReport(record: DecodedAvlRecord): GatewayIngestReport {
  const hasFix = record.gps.latitude !== 0 || record.gps.longitude !== 0;
  const ioElements: Record<string, string> = {};
  for (const [id, value] of record.io.elements) {
    ioElements[String(id)] = value.toString();
  }
  for (const [id, value] of record.io.variableLengthElements) {
    ioElements[String(id)] = value.toString("hex");
  }
  return {
    reportType: hasFix ? "location" : "heartbeat",
    eventAt: new Date(Number(record.timestampMs)).toISOString(),
    longitude: hasFix ? record.gps.longitude : null,
    latitude: hasFix ? record.gps.latitude : null,
    altitudeMeters: record.gps.altitudeMeters,
    headingDegrees: record.gps.angleDegrees,
    speedKmh: record.gps.speedKmh,
    satelliteCount: record.gps.satellites,
    rawCodecId: "8E",
    ioElements,
  };
}

export interface GpsGatewayServerOptions {
  ingestClient: GpsGatewayIngestClientLike;
  buffer: DurableTelemetryBuffer;
  gatewayInstanceLabel: string;
  onLog?: (line: string) => void;
}

export class GpsGatewayServer {
  private readonly server: Server;
  readonly metrics: GpsGatewayServerMetrics = {
    connectionsOpened: 0,
    handshakesAccepted: 0,
    handshakesRejected: 0,
    packetsDecoded: 0,
    packetsRejected: 0,
    reportsIngestedLive: 0,
    reportsBuffered: 0,
  };

  private readonly ingestClient: GpsGatewayIngestClientLike;
  private readonly buffer: DurableTelemetryBuffer;
  private readonly log: (line: string) => void;

  constructor(options: GpsGatewayServerOptions) {
    this.ingestClient = options.ingestClient;
    this.buffer = options.buffer;
    this.log = options.onLog ?? (() => {});
    this.server = createServer((socket) => this.handleConnection(socket));
  }

  listen(port: number, host: string): Promise<void> {
    return new Promise((resolve, reject) => {
      this.server.once("error", reject);
      this.server.listen(port, host, () => {
        this.server.removeListener("error", reject);
        resolve();
      });
    });
  }

  /** The actual bound TCP port -- useful when listen() was called with port 0 (an OS-assigned ephemeral port, this package's own test suite's own pattern for a collision-free port per test). */
  get boundPort(): number {
    const address = this.server.address();
    if (typeof address !== "object" || address === null) {
      throw new Error("server_not_listening: boundPort read before listen() resolved");
    }
    return address.port;
  }

  close(): Promise<void> {
    return new Promise((resolve, reject) => {
      this.server.close((error) => (error ? reject(error) : resolve()));
    });
  }

  private handleConnection(socket: Socket): void {
    this.metrics.connectionsOpened += 1;
    let accumulator: Bytes = Buffer.alloc(0);
    let state: ConnectionState = { phase: "awaiting_handshake" };
    let closed = false;
    // Serializes 'data' event processing -- Node can fire another 'data' event before
    // an async drainAccumulator() call for the previous chunk has finished awaiting an
    // RPC round-trip; without this chain, two overlapping drains would each capture a
    // stale accumulator/state snapshot and corrupt/duplicate the byte stream.
    let processingChain: Promise<void> = Promise.resolve();

    const closeWithLog = (reason: string) => {
      if (closed) {
        return;
      }
      closed = true;
      this.log(`connection closed: ${reason}`);
      socket.destroy();
    };

    socket.on("data", (chunk: Bytes) => {
      if (closed) {
        return;
      }
      accumulator = Buffer.concat([accumulator, chunk]);

      if (accumulator.length > MAX_BUFFERED_BYTES) {
        this.metrics.packetsRejected += 1;
        closeWithLog("oversized_packet");
        return;
      }

      processingChain = processingChain
        .then(() => {
          if (closed) {
            return;
          }
          return this.drainAccumulator(socket, accumulator, state, (nextAccumulator, nextState) => {
            accumulator = nextAccumulator;
            state = nextState;
          }, closeWithLog);
        })
        .catch((error: Error) => {
          // Guards against an unhandled rejection AND against the chain staying
          // permanently rejected (which would silently stop processing every
          // subsequent chunk on this connection) -- any error reaching here is one
          // drainAccumulator's own try/catch blocks did not already convert into a
          // clean closeWithLog() call (e.g. a filesystem error from the durable
          // buffer), so it is itself a reason to close the connection.
          closeWithLog(`unexpected_processing_error: ${error.message}`);
        });
    });

    socket.on("error", (error) => {
      this.log(`socket error: ${error.message}`);
    });
  }

  private async drainAccumulator(
    socket: Socket,
    initialAccumulator: Bytes,
    initialState: ConnectionState,
    commit: (accumulator: Bytes, state: ConnectionState) => void,
    closeWithLog: (reason: string) => void,
  ): Promise<void> {
    let accumulator = initialAccumulator;
    let state = initialState;

    for (;;) {
      if (state.phase === "awaiting_handshake") {
        let handshake;
        try {
          handshake = decodeImeiHandshake(accumulator);
        } catch (error) {
          this.metrics.handshakesRejected += 1;
          closeWithLog(`malformed_handshake: ${(error as Error).message}`);
          return;
        }
        if (!handshake) {
          break;
        }
        accumulator = accumulator.subarray(handshake.bytesConsumed);

        let result;
        try {
          result = await this.ingestClient.resolveHandshake(handshake.imei);
        } catch (error) {
          this.metrics.handshakesRejected += 1;
          socket.write(encodeHandshakeResponse(false));
          closeWithLog(`handshake_authentication_failed: ${(error as Error).message}`);
          return;
        }

        if (!result.accepted || !result.deviceId) {
          this.metrics.handshakesRejected += 1;
          socket.write(encodeHandshakeResponse(false));
          closeWithLog(`handshake_rejected: ${result.rejectionReason ?? "unknown"}`);
          return;
        }

        this.metrics.handshakesAccepted += 1;
        socket.write(encodeHandshakeResponse(true));
        state = { phase: "awaiting_avl_data", deviceId: result.deviceId, imei: handshake.imei };
        continue;
      }

      // awaiting_avl_data
      let decoded;
      try {
        decoded = decodeAvlDataPacket(accumulator);
      } catch (error) {
        this.metrics.packetsRejected += 1;
        closeWithLog(`malformed_avl_packet: ${(error as Error).message}`);
        return;
      }
      if (!decoded) {
        break;
      }
      accumulator = accumulator.subarray(decoded.bytesConsumed);
      this.metrics.packetsDecoded += 1;

      const reports = decoded.packet.records.map(recordToReport);
      try {
        await this.ingestClient.ingestBatch(state.deviceId, reports);
        this.metrics.reportsIngestedLive += reports.length;
      } catch (error) {
        this.log(`live ingest failed, buffering durably: ${(error as Error).message}`);
        await this.buffer.enqueue({ deviceId: state.deviceId, reports, enqueuedAt: new Date().toISOString() });
        this.metrics.reportsBuffered += reports.length;
      }

      socket.write(encodeAckResponse(decoded.packet.records.length));
    }

    commit(accumulator, state);
  }
}
