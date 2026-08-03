/**
 * Teltonika Codec 8 Extended binary protocol -- IMEI handshake, AVL data packet
 * decoding, and CRC-16/IBM (ARC) validation (ATW-226D, 226_GPS_TELEMATICS_INTEGRATION_
 * PROMPT.md §14B). A deliberately real, byte-level implementation of the publicly
 * documented Teltonika wire protocol (FMC920 and every other Codec 8 Extended device),
 * not a simplified stand-in -- every offset/width below matches the vendor's own
 * published frame layout.
 *
 * `encodeAvlDataPacket` (the inverse of `decodeAvlDataPacket`) exists purely as a test/
 * simulator helper -- a real device never receives this module's own encoded bytes back;
 * it lets this package's own test suite and any future local hardware simulator produce
 * a genuinely protocol-correct fixture packet instead of a hand-typed byte array that
 * might not reflect the real wire format.
 */

export const CODEC_8_EXTENDED_ID = 0x8e;

/** TypeScript 5.9's Buffer is generic over its backing ArrayBufferLike; Buffer.concat()/subarray() widen to Buffer<ArrayBufferLike>, which a bare `Buffer` (= Buffer<ArrayBuffer>) parameter/variable cannot accept. Every signature in this package that receives or returns a sliced/concatenated buffer uses this wider alias instead, so the accumulator produced by socket 'data' events (server.ts) type-checks end to end. */
export type Bytes = Buffer<ArrayBufferLike>;

/** CRC-16/IBM (ARC): polynomial 0xA001, initial value 0x0000, no final XOR -- Teltonika's own documented algorithm for the AVL data packet's trailing checksum. */
export function crc16Ibm(data: Bytes): number {
  let crc = 0x0000;
  for (const byte of data) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) {
      if ((crc & 0x0001) !== 0) {
        crc = (crc >>> 1) ^ 0xa001;
      } else {
        crc = crc >>> 1;
      }
    }
  }
  return crc & 0xffff;
}

export interface ImeiHandshake {
  imei: string;
  bytesConsumed: number;
}

/** The device's own connection-opening frame: a 2-byte big-endian length prefix followed by that many ASCII digits (the IMEI itself). Returns null if the buffer does not yet hold a complete handshake frame -- the caller should wait for more bytes, never treat this as malformed. */
export function decodeImeiHandshake(buffer: Bytes): ImeiHandshake | null {
  if (buffer.length < 2) {
    return null;
  }
  const imeiLength = buffer.readUInt16BE(0);
  if (buffer.length < 2 + imeiLength) {
    return null;
  }
  const imei = buffer.subarray(2, 2 + imeiLength).toString("ascii");
  if (!/^\d+$/.test(imei)) {
    throw new Error(`malformed_imei_handshake: expected an all-digit IMEI, got ${JSON.stringify(imei)}`);
  }
  return { imei, bytesConsumed: 2 + imeiLength };
}

/** The server's own accept/reject reply to the IMEI handshake -- a single byte, 0x01 (accepted, device may proceed) or 0x00 (rejected, server closes the connection immediately after). */
export function encodeHandshakeResponse(accepted: boolean): Bytes {
  return Buffer.from([accepted ? 0x01 : 0x00]);
}

export interface DecodedGpsElement {
  longitude: number;
  latitude: number;
  altitudeMeters: number;
  angleDegrees: number;
  satellites: number;
  speedKmh: number;
}

export interface DecodedIoElements {
  eventIoId: number;
  elements: Map<number, bigint>;
  variableLengthElements: Map<number, Bytes>;
}

export interface DecodedAvlRecord {
  timestampMs: bigint;
  priority: number;
  gps: DecodedGpsElement;
  io: DecodedIoElements;
}

export interface DecodedAvlDataPacket {
  codecId: number;
  records: DecodedAvlRecord[];
}

class ByteReader {
  private offset = 0;
  private readonly buffer: Bytes;

  constructor(buffer: Bytes) {
    this.buffer = buffer;
  }

  get position(): number {
    return this.offset;
  }

  remaining(): number {
    return this.buffer.length - this.offset;
  }

  readUInt8(): number {
    const value = this.buffer.readUInt8(this.offset);
    this.offset += 1;
    return value;
  }

  readUInt16(): number {
    const value = this.buffer.readUInt16BE(this.offset);
    this.offset += 2;
    return value;
  }

  readInt16(): number {
    const value = this.buffer.readInt16BE(this.offset);
    this.offset += 2;
    return value;
  }

  readUInt32(): number {
    const value = this.buffer.readUInt32BE(this.offset);
    this.offset += 4;
    return value;
  }

  readInt32(): number {
    const value = this.buffer.readInt32BE(this.offset);
    this.offset += 4;
    return value;
  }

  readUInt64(): bigint {
    const value = this.buffer.readBigUInt64BE(this.offset);
    this.offset += 8;
    return value;
  }

  readBytes(length: number): Bytes {
    const value = this.buffer.subarray(this.offset, this.offset + length);
    this.offset += length;
    return value;
  }
}

function decodeIoElements(reader: ByteReader): DecodedIoElements {
  const eventIoId = reader.readUInt16();
  const totalCount = reader.readUInt16();
  const elements = new Map<number, bigint>();
  const variableLengthElements = new Map<number, Bytes>();

  const n1 = reader.readUInt16();
  for (let i = 0; i < n1; i++) {
    const id = reader.readUInt16();
    elements.set(id, BigInt(reader.readUInt8()));
  }
  const n2 = reader.readUInt16();
  for (let i = 0; i < n2; i++) {
    const id = reader.readUInt16();
    elements.set(id, BigInt(reader.readUInt16()));
  }
  const n4 = reader.readUInt16();
  for (let i = 0; i < n4; i++) {
    const id = reader.readUInt16();
    elements.set(id, BigInt(reader.readUInt32()));
  }
  const n8 = reader.readUInt16();
  for (let i = 0; i < n8; i++) {
    const id = reader.readUInt16();
    elements.set(id, reader.readUInt64());
  }
  const nx = reader.readUInt16();
  for (let i = 0; i < nx; i++) {
    const id = reader.readUInt16();
    const length = reader.readUInt16();
    variableLengthElements.set(id, reader.readBytes(length));
  }

  const actualCount = n1 + n2 + n4 + n8 + nx;
  if (actualCount !== totalCount) {
    throw new Error(`io_element_count_mismatch: declared ${totalCount} total IO elements, decoded ${actualCount}`);
  }

  return { eventIoId, elements, variableLengthElements };
}

/**
 * Decodes one complete AVL data packet, starting at the 4-byte zero preamble, ending
 * after the trailing CRC-16 -- returns null if the buffer does not yet hold a complete
 * packet (the caller should wait for more bytes). Throws on any structural violation
 * (bad preamble, non-Codec-8-Extended codec ID, record-count mismatch, CRC mismatch,
 * truncated/oversized element) -- a raw TCP listener has no other caller to defer
 * validation to, unlike this repository's own anon-facing HTTPS RPCs.
 */
export function decodeAvlDataPacket(buffer: Bytes): { packet: DecodedAvlDataPacket; bytesConsumed: number } | null {
  if (buffer.length < 8) {
    return null;
  }
  const preamble = buffer.readUInt32BE(0);
  if (preamble !== 0) {
    throw new Error(`invalid_preamble: expected 0x00000000, got 0x${preamble.toString(16).padStart(8, "0")}`);
  }
  const dataFieldLength = buffer.readUInt32BE(4);
  const totalFrameLength = 8 + dataFieldLength + 4;
  if (buffer.length < totalFrameLength) {
    return null;
  }

  const dataField = buffer.subarray(8, 8 + dataFieldLength);
  const crcField = buffer.subarray(8 + dataFieldLength, totalFrameLength);
  const expectedCrc = crcField.readUInt32BE(0);
  const actualCrc = crc16Ibm(dataField);
  if (expectedCrc !== actualCrc) {
    throw new Error(`crc_mismatch: frame CRC 0x${expectedCrc.toString(16)} does not match computed CRC 0x${actualCrc.toString(16)}`);
  }

  const reader = new ByteReader(dataField);
  const codecId = reader.readUInt8();
  if (codecId !== CODEC_8_EXTENDED_ID) {
    throw new Error(`unsupported_codec_id: expected Codec 8 Extended (0x8E), got 0x${codecId.toString(16)}`);
  }

  const declaredRecordCount = reader.readUInt8();
  const records: DecodedAvlRecord[] = [];
  for (let i = 0; i < declaredRecordCount; i++) {
    const timestampMs = reader.readUInt64();
    const priority = reader.readUInt8();
    const gps: DecodedGpsElement = {
      longitude: reader.readInt32() / 10_000_000,
      latitude: reader.readInt32() / 10_000_000,
      altitudeMeters: reader.readInt16(),
      angleDegrees: reader.readUInt16(),
      satellites: reader.readUInt8(),
      speedKmh: reader.readUInt16(),
    };
    const io = decodeIoElements(reader);
    records.push({ timestampMs, priority, gps, io });
  }

  const trailingRecordCount = reader.readUInt8();
  if (trailingRecordCount !== declaredRecordCount) {
    throw new Error(`record_count_mismatch: header declared ${declaredRecordCount}, trailer declared ${trailingRecordCount}`);
  }
  if (reader.remaining() !== 0) {
    throw new Error(`trailing_bytes: ${reader.remaining()} unconsumed byte(s) after decoding ${declaredRecordCount} record(s)`);
  }

  return { packet: { codecId, records }, bytesConsumed: totalFrameLength };
}

/** The server's own ACK reply after a successfully decoded AVL data packet -- a 4-byte big-endian count of accepted records, the real Teltonika protocol's own acknowledgment shape (the device retransmits the whole packet if this count does not match what it sent). */
export function encodeAckResponse(acceptedRecordCount: number): Bytes {
  const buffer = Buffer.alloc(4);
  buffer.writeUInt32BE(acceptedRecordCount, 0);
  return buffer;
}

export interface EncodeAvlRecordInput {
  timestampMs: bigint;
  priority: number;
  longitude: number;
  latitude: number;
  altitudeMeters: number;
  angleDegrees: number;
  satellites: number;
  speedKmh: number;
  eventIoId?: number;
  ioElements1?: Map<number, number>;
  ioElements2?: Map<number, number>;
  ioElements4?: Map<number, number>;
  ioElements8?: Map<number, bigint>;
  ioElementsVariable?: Map<number, Bytes>;
}

/** Test/simulator helper only -- see this module's own header. */
export function encodeAvlDataPacket(records: EncodeAvlRecordInput[]): Bytes {
  const recordBuffers = records.map((record) => {
    const parts: Bytes[] = [];
    const header = Buffer.alloc(8 + 1 + 4 + 4 + 2 + 2 + 1 + 2);
    let offset = 0;
    header.writeBigUInt64BE(record.timestampMs, offset);
    offset += 8;
    header.writeUInt8(record.priority, offset);
    offset += 1;
    header.writeInt32BE(Math.round(record.longitude * 10_000_000), offset);
    offset += 4;
    header.writeInt32BE(Math.round(record.latitude * 10_000_000), offset);
    offset += 4;
    header.writeInt16BE(record.altitudeMeters, offset);
    offset += 2;
    header.writeUInt16BE(record.angleDegrees, offset);
    offset += 2;
    header.writeUInt8(record.satellites, offset);
    offset += 1;
    header.writeUInt16BE(record.speedKmh, offset);
    parts.push(header);

    const e1 = [...(record.ioElements1 ?? new Map<number, number>()).entries()];
    const e2 = [...(record.ioElements2 ?? new Map<number, number>()).entries()];
    const e4 = [...(record.ioElements4 ?? new Map<number, number>()).entries()];
    const e8 = [...(record.ioElements8 ?? new Map<number, bigint>()).entries()];
    const ex = [...(record.ioElementsVariable ?? new Map<number, Bytes>()).entries()];
    const totalCount = e1.length + e2.length + e4.length + e8.length + ex.length;

    const ioHeader = Buffer.alloc(2 + 2 + 2);
    ioHeader.writeUInt16BE(record.eventIoId ?? 0, 0);
    ioHeader.writeUInt16BE(totalCount, 2);
    ioHeader.writeUInt16BE(e1.length, 4);
    parts.push(ioHeader);
    for (const [id, value] of e1) {
      const entry = Buffer.alloc(2 + 1);
      entry.writeUInt16BE(id, 0);
      entry.writeUInt8(value, 2);
      parts.push(entry);
    }

    const n2Header = Buffer.alloc(2);
    n2Header.writeUInt16BE(e2.length, 0);
    parts.push(n2Header);
    for (const [id, value] of e2) {
      const entry = Buffer.alloc(2 + 2);
      entry.writeUInt16BE(id, 0);
      entry.writeUInt16BE(value, 2);
      parts.push(entry);
    }

    const n4Header = Buffer.alloc(2);
    n4Header.writeUInt16BE(e4.length, 0);
    parts.push(n4Header);
    for (const [id, value] of e4) {
      const entry = Buffer.alloc(2 + 4);
      entry.writeUInt16BE(id, 0);
      entry.writeUInt32BE(value, 2);
      parts.push(entry);
    }

    const n8Header = Buffer.alloc(2);
    n8Header.writeUInt16BE(e8.length, 0);
    parts.push(n8Header);
    for (const [id, value] of e8) {
      const entry = Buffer.alloc(2 + 8);
      entry.writeUInt16BE(id, 0);
      entry.writeBigUInt64BE(value, 2);
      parts.push(entry);
    }

    const nxHeader = Buffer.alloc(2);
    nxHeader.writeUInt16BE(ex.length, 0);
    parts.push(nxHeader);
    for (const [id, value] of ex) {
      const entryHeader = Buffer.alloc(2 + 2);
      entryHeader.writeUInt16BE(id, 0);
      entryHeader.writeUInt16BE(value.length, 2);
      parts.push(entryHeader, value);
    }

    return Buffer.concat(parts);
  });

  const recordCount = records.length;
  const dataField = Buffer.concat([
    Buffer.from([CODEC_8_EXTENDED_ID, recordCount]),
    ...recordBuffers,
    Buffer.from([recordCount]),
  ]);
  const crc = crc16Ibm(dataField);
  const crcField = Buffer.alloc(4);
  crcField.writeUInt32BE(crc, 0);

  const lengthField = Buffer.alloc(4);
  lengthField.writeUInt32BE(dataField.length, 0);

  return Buffer.concat([Buffer.alloc(4), lengthField, dataField, crcField]);
}
