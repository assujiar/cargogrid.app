import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { parseCustomerDocument, CUSTOMER_DOCUMENT_SOURCE_MODULES, CUSTOMER_DOCUMENT_LIVE_SOURCE_MODULES } from "./customer-document.ts";

const DOCUMENT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ENTITY_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "623e4567-e89b-12d3-a456-426614174000";

const QUOTE_REQUEST_ROW = {
  document_id: DOCUMENT_ID,
  source_module: "quote_request",
  source_entity_id: ENTITY_ID,
  document_type: "quote_request_attachment",
  original_filename: "cargo-photo.jpg",
  mime_type: "image/jpeg",
  size_bytes: 204800,
  malware_scan_status: "clean",
  account_id: ACCOUNT_ID,
  created_at: "2026-08-16T02:00:00.000Z",
};

const EPOD_ROW = {
  ...QUOTE_REQUEST_ROW,
  source_module: "epod",
  document_type: "epod_signature",
  original_filename: "signature.png",
  mime_type: "image/png",
  malware_scan_status: "pending",
};

describe("parseCustomerDocument", () => {
  test("maps a quote_request document row", () => {
    const parsed = parseCustomerDocument(QUOTE_REQUEST_ROW);
    assert.equal(parsed.documentId, DOCUMENT_ID);
    assert.equal(parsed.sourceModule, "quote_request");
    assert.equal(parsed.documentType, "quote_request_attachment");
    assert.equal(parsed.malwareScanStatus, "clean");
  });

  test("maps an epod document row, surfacing a non-clean scan status honestly, never hidden or defaulted", () => {
    const parsed = parseCustomerDocument(EPOD_ROW);
    assert.equal(parsed.sourceModule, "epod");
    assert.equal(parsed.documentType, "epod_signature");
    assert.equal(parsed.malwareScanStatus, "pending");
  });

  test("rejects an unrecognized sourceModule", () => {
    assert.throws(() => parseCustomerDocument({ ...QUOTE_REQUEST_ROW, source_module: "not_a_real_source" }));
  });

  test("rejects a missing required field", () => {
    assert.throws(() => parseCustomerDocument({ ...QUOTE_REQUEST_ROW, original_filename: undefined }));
  });

  test("the recognized source module enum is exactly the migration's 4-value set", () => {
    assert.deepEqual([...CUSTOMER_DOCUMENT_SOURCE_MODULES], ["quote_request", "epod", "invoice", "ticket"]);
  });

  test("exactly two source modules have a real, live backing union arm today", () => {
    assert.deepEqual([...CUSTOMER_DOCUMENT_LIVE_SOURCE_MODULES], ["quote_request", "epod"]);
    for (const liveModule of CUSTOMER_DOCUMENT_LIVE_SOURCE_MODULES) {
      assert.ok((CUSTOMER_DOCUMENT_SOURCE_MODULES as readonly string[]).includes(liveModule));
    }
  });
});
