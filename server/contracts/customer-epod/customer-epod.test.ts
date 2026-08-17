import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { parseCustomerEpod, EPOD_STATUSES, EPOD_FILE_ROLES } from "./customer-epod.ts";

const SHIPMENT_ID = "423e4567-e89b-12d3-a456-426614174000";
const CAPTURE_ID = "523e4567-e89b-12d3-a456-426614174000";
const FILE_ID = "623e4567-e89b-12d3-a456-426614174000";

const NOT_AVAILABLE_ROW = {
  shipment_order_id: SHIPMENT_ID,
  epod_status: "not_available",
  epod_capture_id: null,
  receiver_name: null,
  captured_at: null,
  server_received_at: null,
  files: [],
};

const AVAILABLE_ROW = {
  shipment_order_id: SHIPMENT_ID,
  epod_status: "available",
  epod_capture_id: CAPTURE_ID,
  receiver_name: "Jane Receiver",
  captured_at: "2026-08-16T02:00:00.000Z",
  server_received_at: "2026-08-16T02:00:05.000Z",
  files: [
    { fileId: FILE_ID, role: "signature", originalFilename: "signature.png", mimeType: "image/png", sizeBytes: 20480 },
    { fileId: "723e4567-e89b-12d3-a456-426614174000", role: "photo", originalFilename: "photo-1.jpg", mimeType: "image/jpeg", sizeBytes: 102400 },
  ],
};

const QUARANTINED_ROW = {
  ...AVAILABLE_ROW,
  epod_status: "quarantined",
  files: [],
};

describe("parseCustomerEpod", () => {
  test("maps a not_available response with no capture and an empty file list", () => {
    const parsed = parseCustomerEpod(NOT_AVAILABLE_ROW);
    assert.equal(parsed.epodStatus, "not_available");
    assert.equal(parsed.epodCaptureId, null);
    assert.equal(parsed.receiverName, null);
    assert.deepEqual(parsed.files, []);
  });

  test("maps an available response, files already camelCased, never carrying storagePath", () => {
    const parsed = parseCustomerEpod(AVAILABLE_ROW);
    assert.equal(parsed.epodStatus, "available");
    assert.equal(parsed.epodCaptureId, CAPTURE_ID);
    assert.equal(parsed.receiverName, "Jane Receiver");
    assert.equal(parsed.files.length, 2);
    assert.equal(parsed.files[0]?.role, "signature");
    assert.equal(parsed.files[1]?.role, "photo");
    assert.deepEqual(Object.keys(parsed.files[0] ?? {}).sort(), ["fileId", "mimeType", "originalFilename", "role", "sizeBytes"]);
  });

  test("maps a quarantined response -- capture metadata still present, files withheld entirely", () => {
    const parsed = parseCustomerEpod(QUARANTINED_ROW);
    assert.equal(parsed.epodStatus, "quarantined");
    assert.equal(parsed.epodCaptureId, CAPTURE_ID);
    assert.equal(parsed.receiverName, "Jane Receiver");
    assert.deepEqual(parsed.files, []);
  });

  test("parses a JSON-string-encoded files array, never throws", () => {
    const parsed = parseCustomerEpod({ ...NOT_AVAILABLE_ROW, epod_status: "available", epod_capture_id: CAPTURE_ID, files: JSON.stringify(AVAILABLE_ROW.files) });
    assert.equal(parsed.files.length, 2);
  });

  test("defaults a missing files field to empty, never throws", () => {
    const parsed = parseCustomerEpod({ ...NOT_AVAILABLE_ROW, files: undefined });
    assert.deepEqual(parsed.files, []);
  });

  test("rejects an unrecognized epodStatus", () => {
    assert.throws(() => parseCustomerEpod({ ...NOT_AVAILABLE_ROW, epod_status: "not_a_real_status" }));
  });

  test("rejects an unrecognized file role", () => {
    assert.throws(() => parseCustomerEpod({ ...AVAILABLE_ROW, files: [{ ...AVAILABLE_ROW.files[0], role: "not_a_real_role" }] }));
  });

  test("every real epod status is exactly the migration's 3-value set", () => {
    assert.deepEqual([...EPOD_STATUSES], ["not_available", "quarantined", "available"]);
  });

  test("every real file role is exactly the migration's 2-value set", () => {
    assert.deepEqual([...EPOD_FILE_ROLES], ["signature", "photo"]);
  });
});
