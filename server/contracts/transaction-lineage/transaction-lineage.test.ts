import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { parseTransactionLineageEdge, parseTransactionLineageManifest, parseTransactionLineageAnomaly } from "./transaction-lineage.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const JOB_ORDER_ID = "223e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const HANDOFF_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const EDGE_ID = "623e4567-e89b-12d3-a456-426614174000";

describe("parseTransactionLineageEdge", () => {
  test("maps a trigger-captured edge row (no actor, system:trigger label)", () => {
    const edge = parseTransactionLineageEdge({
      id: EDGE_ID,
      tenant_id: TENANT_ID,
      relation_type: "job_to_shipment",
      source_type: "job_order",
      source_id: JOB_ORDER_ID,
      target_type: "shipment_order",
      target_id: SHIPMENT_ID,
      source_version_hash: "abc123",
      owner_user_id: ACTOR_ID,
      org_unit_id: null,
      is_override: false,
      override_reason: null,
      created_by_auth_user_id: null,
      created_by_label: "system:trigger",
      created_at: "2026-07-28T00:00:00Z",
    });
    assert.equal(edge.relationType, "job_to_shipment");
    assert.equal(edge.isOverride, false);
    assert.equal(edge.createdByAuthUserId, null);
    assert.equal(edge.createdByLabel, "system:trigger");
  });

  test("maps an authorized override row", () => {
    const edge = parseTransactionLineageEdge({
      id: EDGE_ID,
      tenant_id: TENANT_ID,
      relation_type: "job_to_shipment",
      source_type: "job_order",
      source_id: JOB_ORDER_ID,
      target_type: "shipment_order",
      target_id: SHIPMENT_ID,
      source_version_hash: null,
      owner_user_id: null,
      org_unit_id: null,
      is_override: true,
      override_reason: "consolidation correction",
      created_by_auth_user_id: ACTOR_ID,
      created_by_label: "rep",
      created_at: "2026-07-28T00:00:00Z",
    });
    assert.equal(edge.isOverride, true);
    assert.equal(edge.overrideReason, "consolidation correction");
    assert.equal(edge.createdByAuthUserId, ACTOR_ID);
  });
});

describe("parseTransactionLineageManifest", () => {
  test("maps the full jsonb manifest shape returned by app.get_transaction_lineage", () => {
    const manifest = parseTransactionLineageManifest({
      jobOrderId: JOB_ORDER_ID,
      jobNumber: "JOB-2026-000001",
      sourceHandoffId: HANDOFF_ID,
      sourceQuotationId: "723e4567-e89b-12d3-a456-426614174000",
      sourcePayloadHash: "hash-value",
      shipments: [
        {
          shipmentOrderId: SHIPMENT_ID,
          shipmentNumber: "SHP-2026-000001",
          status: "closed",
          milestone: { lastMilestoneCode: "delivered", isDelayed: false, currentEta: null },
          epod: { epodCaptureId: "823e4567-e89b-12d3-a456-426614174000", status: "completed", versionNumber: 1 },
          actualCost: { shipmentActualCostId: "923e4567-e89b-12d3-a456-426614174000", status: "approved", versionNumber: 1 },
        },
      ],
      profitability: { jobProfitabilitySnapshotId: "a23e4567-e89b-12d3-a456-426614174000", status: "calculated", versionNumber: 1 },
      billingReadiness: { billingReadinessEvaluationId: "b23e4567-e89b-12d3-a456-426614174000", effectiveStatus: "ready", versionNumber: 1 },
      edges: [
        {
          id: EDGE_ID,
          relationType: "job_to_shipment",
          sourceType: "job_order",
          sourceId: JOB_ORDER_ID,
          targetType: "shipment_order",
          targetId: SHIPMENT_ID,
          sourceVersionHash: "abc123",
          isOverride: false,
          overrideReason: null,
          createdAt: "2026-07-28T00:00:00Z",
        },
      ],
    });
    assert.equal(manifest.shipments.length, 1);
    assert.equal(manifest.shipments[0]?.epod?.status, "completed");
    assert.equal(manifest.profitability?.status, "calculated");
    assert.equal(manifest.billingReadiness?.effectiveStatus, "ready");
    assert.equal(manifest.edges.length, 1);
  });

  test("accepts null shipment children and null profitability/billingReadiness nodes", () => {
    const manifest = parseTransactionLineageManifest({
      jobOrderId: JOB_ORDER_ID,
      jobNumber: "JOB-2026-000002",
      sourceHandoffId: HANDOFF_ID,
      sourceQuotationId: null,
      sourcePayloadHash: null,
      shipments: [
        { shipmentOrderId: SHIPMENT_ID, shipmentNumber: "SHP-2026-000002", status: "draft", milestone: null, epod: null, actualCost: null },
      ],
      profitability: null,
      billingReadiness: null,
      edges: [],
    });
    assert.equal(manifest.shipments[0]?.epod, null);
    assert.equal(manifest.profitability, null);
    assert.equal(manifest.edges.length, 0);
  });
});

describe("parseTransactionLineageAnomaly", () => {
  test("maps an anomaly row", () => {
    const anomaly = parseTransactionLineageAnomaly({
      anomaly_type: "duplicate_target",
      relation_type: "job_to_shipment",
      target_type: "shipment_order",
      target_id: SHIPMENT_ID,
      detail: "target claimed by 2 distinct sources",
    });
    assert.equal(anomaly.anomalyType, "duplicate_target");
    assert.equal(anomaly.targetId, SHIPMENT_ID);
  });
});
