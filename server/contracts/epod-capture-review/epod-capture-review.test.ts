import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { parseEpodCapture } from "./epod-capture-review.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const CAPTURE_ID = "423e4567-e89b-12d3-a456-426614174000";

const BASE_ROW = {
  id: CAPTURE_ID,
  tenant_id: TENANT_ID,
  shipment_order_id: SHIPMENT_ID,
  milestone_event_id: null,
  version_group_id: CAPTURE_ID,
  version_number: 1,
  is_latest_version: true,
  status: "draft",
  receiver_name: null,
  receiver_position: null,
  signature_file_id: null,
  photo_file_ids: [],
  delivery_geog: null,
  captured_at: null,
  server_received_at: "2026-07-28T09:00:00.000Z",
  reviewed_by_auth_user_id: null,
  reviewed_at: null,
  review_notes: null,
  record_version: 1,
  created_by: "rep",
  created_at: "2026-07-28T09:00:00.000Z",
  updated_at: "2026-07-28T09:00:00.000Z",
};

describe("parseEpodCapture", () => {
  test("maps a fresh draft with no evidence", () => {
    const capture = parseEpodCapture(BASE_ROW);
    assert.equal(capture.status, "draft");
    assert.equal(capture.deliveryGeog, null);
    assert.deepEqual(capture.photoFileIds, []);
  });

  test("maps a GeoJSON Point delivery_geog (PostgREST's own automatic geography serialization)", () => {
    const capture = parseEpodCapture({
      ...BASE_ROW,
      status: "submitted",
      receiver_name: "Budi Santoso",
      delivery_geog: { type: "Point", coordinates: [106.845599, -6.208763] },
    });
    assert.equal(capture.deliveryGeog?.coordinates[0], 106.845599);
    assert.equal(capture.receiverName, "Budi Santoso");
  });

  test("maps a completed, reviewed capture", () => {
    const capture = parseEpodCapture({
      ...BASE_ROW,
      status: "completed",
      reviewed_by_auth_user_id: TENANT_ID,
      reviewed_at: "2026-07-28T09:05:00.000Z",
      review_notes: "looks good",
    });
    assert.equal(capture.status, "completed");
    assert.equal(capture.reviewNotes, "looks good");
  });
});
