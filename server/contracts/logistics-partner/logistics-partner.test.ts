import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseLogisticsPartnerEvent,
  parseIngestLogisticsPartnerWebhookEventResult,
  parseLogisticsPartnerDispatchInfo,
  parseLogisticsPartnerConnectionForSync,
  RecordLogisticsPartnerSyncEventInputSchema,
  ReviewLogisticsPartnerEventInputSchema,
} from "./logistics-partner.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const CONNECTION_ID = "323e4567-e89b-12d3-a456-426614174000";
const EVENT_ID = "423e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

describe("parseLogisticsPartnerEvent", () => {
  test("maps snake_case columns to camelCase for a matched event", () => {
    const event = parseLogisticsPartnerEvent({
      id: EVENT_ID,
      tenant_id: TENANT_ID,
      connection_id: CONNECTION_ID,
      provider_event_id: "evt-1",
      event_type: "customs_clearance",
      external_reference: "MSCU1234567",
      shipment_order_id: SHIPMENT_ID,
      match_status: "matched",
      raw_payload: { event_id: "evt-1", event_type: "customs_clearance" },
      processing_status: "received",
      review_notes: null,
      reviewed_by_auth_user_id: null,
      reviewed_at: null,
      created_at: "2026-08-21T00:00:00.000Z",
    });
    assert.equal(event.matchStatus, "matched");
    assert.equal(event.shipmentOrderId, SHIPMENT_ID);
  });

  test("an unmatched event carries a null shipmentOrderId, not a crash", () => {
    const event = parseLogisticsPartnerEvent({
      id: EVENT_ID,
      tenant_id: TENANT_ID,
      connection_id: CONNECTION_ID,
      provider_event_id: "evt-2",
      event_type: "status_update",
      external_reference: "UNKNOWN-REF",
      shipment_order_id: null,
      match_status: "unmatched",
      raw_payload: {},
      processing_status: "received",
      review_notes: null,
      reviewed_by_auth_user_id: null,
      reviewed_at: null,
      created_at: "2026-08-21T00:00:00.000Z",
    });
    assert.equal(event.shipmentOrderId, null);
    assert.equal(event.matchStatus, "unmatched");
  });
});

describe("parseIngestLogisticsPartnerWebhookEventResult", () => {
  test("maps an ok result", () => {
    const result = parseIngestLogisticsPartnerWebhookEventResult({ ingest_status: "ok", event_id: EVENT_ID });
    assert.equal(result.ingestStatus, "ok");
    assert.equal(result.eventId, EVENT_ID);
  });

  test("maps an invalid result with a null event_id", () => {
    const result = parseIngestLogisticsPartnerWebhookEventResult({ ingest_status: "invalid", event_id: null });
    assert.equal(result.ingestStatus, "invalid");
    assert.equal(result.eventId, null);
  });
});

describe("parseLogisticsPartnerDispatchInfo", () => {
  test("maps snake_case columns to camelCase", () => {
    const info = parseLogisticsPartnerDispatchInfo({ connection_id: CONNECTION_ID, connection_status: "active", connection_config: { apiUrl: "https://carrier.example.test/webhooks" } });
    assert.equal(info.connectionStatus, "active");
  });
});

describe("parseLogisticsPartnerConnectionForSync", () => {
  test("maps snake_case columns to camelCase", () => {
    const info = parseLogisticsPartnerConnectionForSync({ tenant_id: TENANT_ID, adapter_code: "port_terminal_edi", connection_status: "active", connection_config: { pollUrl: "https://port.example.test/poll" } });
    assert.equal(info.adapterCode, "port_terminal_edi");
    assert.equal(info.connectionConfig.pollUrl, "https://port.example.test/poll");
  });
});

describe("RecordLogisticsPartnerSyncEventInputSchema", () => {
  test("defaults externalReference to null", () => {
    const parsed = RecordLogisticsPartnerSyncEventInputSchema.parse({
      tenantId: TENANT_ID,
      connectionId: CONNECTION_ID,
      providerEventId: "evt-1",
      eventType: "milestone",
      rawPayload: { event_id: "evt-1" },
      actorAuthUserId: ACTOR_ID,
      actorLabel: "system",
    });
    assert.equal(parsed.externalReference, null);
  });

  test("rejects an unrecognized event type", () => {
    assert.throws(() =>
      RecordLogisticsPartnerSyncEventInputSchema.parse({
        tenantId: TENANT_ID,
        connectionId: CONNECTION_ID,
        providerEventId: "evt-1",
        eventType: "not_a_real_type",
        rawPayload: {},
        actorAuthUserId: ACTOR_ID,
        actorLabel: "system",
      }),
    );
  });
});

describe("ReviewLogisticsPartnerEventInputSchema", () => {
  test("rejects a decision outside reviewed/dismissed", () => {
    assert.throws(() =>
      ReviewLogisticsPartnerEventInputSchema.parse({
        eventId: EVENT_ID,
        decision: "approved",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "system",
      }),
    );
  });

  test("defaults notes to null", () => {
    const parsed = ReviewLogisticsPartnerEventInputSchema.parse({
      eventId: EVENT_ID,
      decision: "reviewed",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "system",
    });
    assert.equal(parsed.notes, null);
  });
});
