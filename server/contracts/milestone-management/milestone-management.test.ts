import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseMilestoneCode,
  parseMilestoneTemplateVersion,
  parseMilestoneEvent,
  parseShipmentMilestoneProjection,
  IngestMilestoneEventInputSchema,
  SetMilestoneTemplateSequenceInputSchema,
  PublishMilestoneTemplateVersionInputSchema,
} from "./milestone-management.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "323e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const EVENT_ID = "623e4567-e89b-12d3-a456-426614174000";

describe("parseMilestoneCode", () => {
  test("maps a real row into camelCase", () => {
    const code = parseMilestoneCode({
      code: "picked_up",
      name: "Picked Up",
      category: "pickup",
      is_customer_visible: true,
      affects_eta: false,
      is_terminal: false,
      registered_by: "tester",
      created_at: "2026-07-27T00:00:00.000Z",
    });
    assert.equal(code.isCustomerVisible, true);
    assert.equal(code.affectsEta, false);
  });
});

describe("parseMilestoneTemplateVersion", () => {
  test("maps a real row including its sequence array", () => {
    const version = parseMilestoneTemplateVersion({
      id: VERSION_ID,
      tenant_id: TENANT_ID,
      mode: "sea",
      status: "published",
      sequence: [{ code: "picked_up" }, { code: "delivered" }],
      supersedes_version_id: null,
      record_version: 2,
      created_by: "rep",
      created_at: "2026-07-27T00:00:00.000Z",
      updated_at: "2026-07-27T00:00:00.000Z",
    });
    assert.equal(version.sequence.length, 2);
    assert.equal(version.sequence[0]?.code, "picked_up");
  });
});

describe("parseMilestoneEvent", () => {
  test("maps a real row, defaulting nullable fields", () => {
    const event = parseMilestoneEvent({
      id: EVENT_ID,
      tenant_id: TENANT_ID,
      shipment_order_id: SHIPMENT_ID,
      milestone_code: "picked_up",
      event_time: "2026-07-27T08:00:00.000Z",
      received_time: "2026-07-27T08:05:00.000Z",
      location: { lat: -6.2, lng: 106.8, label: "Jakarta" },
      source: "manual",
      reason: null,
      corrects_event_id: null,
      idempotency_key: "idem-1",
      sequence_no: 1,
      created_by: "rep",
      created_at: "2026-07-27T08:05:00.000Z",
    });
    assert.equal(event.location?.label, "Jakarta");
    assert.equal(event.correctsEventId, null);
  });
});

describe("parseShipmentMilestoneProjection", () => {
  test("maps a real row, defaulting nullable fields", () => {
    const projection = parseShipmentMilestoneProjection({
      shipment_order_id: SHIPMENT_ID,
      tenant_id: TENANT_ID,
      last_milestone_code: "in_transit",
      last_milestone_event_time: "2026-07-27T14:00:00.000Z",
      last_milestone_received_time: "2026-07-27T14:10:00.000Z",
      current_eta: "2026-07-27T14:00:00.000Z",
      current_location: null,
      is_delayed: false,
      event_count: 2,
      record_version: 2,
      updated_at: "2026-07-27T14:10:00.000Z",
    });
    assert.equal(projection.lastMilestoneCode, "in_transit");
    assert.equal(projection.currentLocation, null);
  });
});

describe("IngestMilestoneEventInputSchema", () => {
  test("rejects an unsupported source", () => {
    assert.throws(() =>
      IngestMilestoneEventInputSchema.parse({
        shipmentOrderId: SHIPMENT_ID,
        milestoneCode: "picked_up",
        eventTime: "2026-07-27T08:00:00.000Z",
        source: "carrier_pigeon",
        idempotencyKey: "idem-1",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });

  test("defaults receivedTime/location/reason/correctsEventId to null", () => {
    const parsed = IngestMilestoneEventInputSchema.parse({
      shipmentOrderId: SHIPMENT_ID,
      milestoneCode: "picked_up",
      eventTime: "2026-07-27T08:00:00.000Z",
      source: "manual",
      idempotencyKey: "idem-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(parsed.receivedTime, null);
    assert.equal(parsed.location, null);
    assert.equal(parsed.reason, null);
    assert.equal(parsed.correctsEventId, null);
  });
});

describe("SetMilestoneTemplateSequenceInputSchema", () => {
  test("rejects an element with an empty code", () => {
    assert.throws(() =>
      SetMilestoneTemplateSequenceInputSchema.parse({
        versionId: VERSION_ID,
        sequence: [{ code: "" }],
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });
});

describe("PublishMilestoneTemplateVersionInputSchema", () => {
  test("requires a positive expectedVersion", () => {
    assert.throws(() =>
      PublishMilestoneTemplateVersionInputSchema.parse({
        versionId: VERSION_ID,
        expectedVersion: 0,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });

  test("defaults supersedesVersionId to null", () => {
    const parsed = PublishMilestoneTemplateVersionInputSchema.parse({
      versionId: VERSION_ID,
      expectedVersion: 1,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(parsed.supersedesVersionId, null);
  });
});
