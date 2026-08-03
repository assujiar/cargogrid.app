import { test } from "node:test";
import assert from "node:assert/strict";
import {
  crc16Ibm,
  decodeImeiHandshake,
  encodeHandshakeResponse,
  decodeAvlDataPacket,
  encodeAvlDataPacket,
  encodeAckResponse,
  CODEC_8_EXTENDED_ID,
} from "../src/codec8e.ts";

test("crc16Ibm matches the standard CRC-16/ARC check value for the ASCII string '123456789'", () => {
  assert.equal(crc16Ibm(Buffer.from("123456789", "ascii")), 0xbb3d);
});

test("crc16Ibm of an empty buffer is zero", () => {
  assert.equal(crc16Ibm(Buffer.alloc(0)), 0x0000);
});

test("decodeImeiHandshake reads a 2-byte length prefix plus that many ASCII digits", () => {
  const imei = "861112030001234";
  const buffer = Buffer.concat([Buffer.from([0x00, imei.length]), Buffer.from(imei, "ascii")]);
  const result = decodeImeiHandshake(buffer);
  assert.deepEqual(result, { imei, bytesConsumed: 2 + imei.length });
});

test("decodeImeiHandshake returns null on a truncated buffer (wait for more bytes, not an error)", () => {
  const imei = "861112030001234";
  const buffer = Buffer.concat([Buffer.from([0x00, imei.length]), Buffer.from(imei.slice(0, 5), "ascii")]);
  assert.equal(decodeImeiHandshake(buffer), null);
});

test("decodeImeiHandshake returns null for fewer than 2 bytes", () => {
  assert.equal(decodeImeiHandshake(Buffer.from([0x00])), null);
});

test("decodeImeiHandshake throws on a non-digit IMEI payload", () => {
  const buffer = Buffer.concat([Buffer.from([0x00, 0x04]), Buffer.from("ABCD", "ascii")]);
  assert.throws(() => decodeImeiHandshake(buffer), /malformed_imei_handshake/);
});

test("encodeHandshakeResponse produces the single accept/reject byte", () => {
  assert.deepEqual(encodeHandshakeResponse(true), Buffer.from([0x01]));
  assert.deepEqual(encodeHandshakeResponse(false), Buffer.from([0x00]));
});

test("encodeAckResponse produces a 4-byte big-endian record count", () => {
  assert.deepEqual(encodeAckResponse(3), Buffer.from([0x00, 0x00, 0x00, 0x03]));
});

test("decodeAvlDataPacket: a hand-built single-record packet (independent of the encoder) decodes every field exactly", () => {
  // Hand-constructed byte-by-byte, deliberately not routed through encodeAvlDataPacket,
  // to independently exercise the decoder's own offset arithmetic.
  const timestampMs = 1_785_000_000_000n;
  const longitude = 106.845599;
  const latitude = -6.208763;

  // Over-allocated, then trimmed to the real used length below -- avoids a hand-tallied
  // byte-count expression (this test's whole point is independence from the encoder's
  // own field widths, not a second place to make the identical off-by-N mistake).
  const scratch = Buffer.alloc(96);
  let o = 0;
  scratch.writeBigUInt64BE(timestampMs, o); o += 8;
  scratch.writeUInt8(1, o); o += 1; // priority
  scratch.writeInt32BE(Math.round(longitude * 10_000_000), o); o += 4;
  scratch.writeInt32BE(Math.round(latitude * 10_000_000), o); o += 4;
  scratch.writeInt16BE(12, o); o += 2; // altitude
  scratch.writeUInt16BE(90, o); o += 2; // angle
  scratch.writeUInt8(8, o); o += 1; // satellites
  scratch.writeUInt16BE(40, o); o += 2; // speed
  scratch.writeUInt16BE(0, o); o += 2; // event io id
  scratch.writeUInt16BE(1, o); o += 2; // total io count
  scratch.writeUInt16BE(0, o); o += 2; // n1
  scratch.writeUInt16BE(0, o); o += 2; // n2
  scratch.writeUInt16BE(0, o); o += 2; // n4
  scratch.writeUInt16BE(1, o); o += 2; // n8
  scratch.writeUInt16BE(0xef, o); o += 2; // io id 239 (ignition, a real Teltonika IO id)
  scratch.writeBigUInt64BE(1n, o); o += 8;
  scratch.writeUInt16BE(0, o); o += 2; // nx
  const record = scratch.subarray(0, o);

  const dataField = Buffer.concat([Buffer.from([CODEC_8_EXTENDED_ID, 0x01]), record, Buffer.from([0x01])]);
  const crc = crc16Ibm(dataField);
  const crcField = Buffer.alloc(4);
  crcField.writeUInt32BE(crc, 0);
  const lengthField = Buffer.alloc(4);
  lengthField.writeUInt32BE(dataField.length, 0);
  const packetBuffer = Buffer.concat([Buffer.alloc(4), lengthField, dataField, crcField]);

  const result = decodeAvlDataPacket(packetBuffer);
  assert.ok(result);
  assert.equal(result.bytesConsumed, packetBuffer.length);
  assert.equal(result.packet.codecId, CODEC_8_EXTENDED_ID);
  assert.equal(result.packet.records.length, 1);
  const decoded = result.packet.records[0]!;
  assert.equal(decoded.timestampMs, timestampMs);
  assert.equal(decoded.priority, 1);
  assert.equal(decoded.gps.longitude, longitude);
  assert.equal(decoded.gps.latitude, latitude);
  assert.equal(decoded.gps.altitudeMeters, 12);
  assert.equal(decoded.gps.angleDegrees, 90);
  assert.equal(decoded.gps.satellites, 8);
  assert.equal(decoded.gps.speedKmh, 40);
  assert.equal(decoded.io.elements.get(0xef), 1n);
});

test("decodeAvlDataPacket: negative altitude (below sea level) round-trips through the encoder correctly", () => {
  const packet = encodeAvlDataPacket([
    { timestampMs: 1n, priority: 0, longitude: 0, latitude: 0, altitudeMeters: -25, angleDegrees: 0, satellites: 0, speedKmh: 0 },
  ]);
  const result = decodeAvlDataPacket(packet);
  assert.equal(result?.packet.records[0]?.gps.altitudeMeters, -25);
});

test("decodeAvlDataPacket: a multi-record packet with every IO element width (1/2/4/8-byte and variable-length) round-trips exactly", () => {
  const packet = encodeAvlDataPacket([
    {
      timestampMs: 1_000n,
      priority: 1,
      longitude: 10.5,
      latitude: -20.25,
      altitudeMeters: 100,
      angleDegrees: 180,
      satellites: 12,
      speedKmh: 60,
      eventIoId: 239,
      ioElements1: new Map([[239, 1]]),
      ioElements2: new Map([[66, 12588]]),
      ioElements4: new Map([[16, 123456]]),
      ioElements8: new Map([[389, 987654321n]]),
      ioElementsVariable: new Map([[757, Buffer.from("hello", "ascii")]]),
    },
    {
      timestampMs: 2_000n,
      priority: 0,
      longitude: -10.5,
      latitude: 20.25,
      altitudeMeters: 50,
      angleDegrees: 0,
      satellites: 5,
      speedKmh: 0,
    },
  ]);

  const result = decodeAvlDataPacket(packet);
  assert.ok(result);
  assert.equal(result.packet.records.length, 2);

  const first = result.packet.records[0]!;
  assert.equal(first.io.eventIoId, 239);
  assert.equal(first.io.elements.get(239), 1n);
  assert.equal(first.io.elements.get(66), 12588n);
  assert.equal(first.io.elements.get(16), 123456n);
  assert.equal(first.io.elements.get(389), 987654321n);
  assert.deepEqual(first.io.variableLengthElements.get(757), Buffer.from("hello", "ascii"));

  const second = result.packet.records[1]!;
  assert.equal(second.gps.longitude, -10.5);
  assert.equal(second.gps.satellites, 5);
});

test("decodeAvlDataPacket returns null on a packet whose declared data length exceeds the available bytes (wait for more)", () => {
  const full = encodeAvlDataPacket([{ timestampMs: 1n, priority: 0, longitude: 0, latitude: 0, altitudeMeters: 0, angleDegrees: 0, satellites: 0, speedKmh: 0 }]);
  const truncated = full.subarray(0, full.length - 5);
  assert.equal(decodeAvlDataPacket(truncated), null);
});

test("decodeAvlDataPacket throws on a non-zero preamble", () => {
  const full = encodeAvlDataPacket([{ timestampMs: 1n, priority: 0, longitude: 0, latitude: 0, altitudeMeters: 0, angleDegrees: 0, satellites: 0, speedKmh: 0 }]);
  full.writeUInt8(0x01, 0);
  assert.throws(() => decodeAvlDataPacket(full), /invalid_preamble/);
});

test("decodeAvlDataPacket throws on a CRC mismatch (corrupted frame)", () => {
  const full = encodeAvlDataPacket([{ timestampMs: 1n, priority: 0, longitude: 0, latitude: 0, altitudeMeters: 0, angleDegrees: 0, satellites: 0, speedKmh: 0 }]);
  full.writeUInt8(full.readUInt8(full.length - 1) ^ 0xff, full.length - 1);
  assert.throws(() => decodeAvlDataPacket(full), /crc_mismatch/);
});

test("decodeAvlDataPacket throws on an unsupported codec ID", () => {
  const full = encodeAvlDataPacket([{ timestampMs: 1n, priority: 0, longitude: 0, latitude: 0, altitudeMeters: 0, angleDegrees: 0, satellites: 0, speedKmh: 0 }]);
  // codec id is the first byte of the data field, at offset 8; recompute CRC afterward
  // since altering it changes the data field the CRC is computed over.
  const dataFieldLength = full.readUInt32BE(4);
  const mutated = Buffer.from(full);
  mutated.writeUInt8(0x08, 8); // Codec 8 (not Extended) -- unsupported by this decoder
  const dataField = mutated.subarray(8, 8 + dataFieldLength);
  mutated.writeUInt32BE(crc16Ibm(dataField), 8 + dataFieldLength);
  assert.throws(() => decodeAvlDataPacket(mutated), /unsupported_codec_id/);
});

test("decodeAvlDataPacket throws on a leading/trailing record-count mismatch", () => {
  const full = encodeAvlDataPacket([{ timestampMs: 1n, priority: 0, longitude: 0, latitude: 0, altitudeMeters: 0, angleDegrees: 0, satellites: 0, speedKmh: 0 }]);
  const dataFieldLength = full.readUInt32BE(4);
  const trailingCountOffset = 8 + dataFieldLength - 1; // last byte of the data field
  const mutated = Buffer.from(full);
  mutated.writeUInt8(2, trailingCountOffset);
  const dataField = mutated.subarray(8, 8 + dataFieldLength);
  mutated.writeUInt32BE(crc16Ibm(dataField), 8 + dataFieldLength);
  assert.throws(() => decodeAvlDataPacket(mutated), /record_count_mismatch/);
});
