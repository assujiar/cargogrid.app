import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseVendorComparison,
  parseVendorComparisonOffer,
  parseVendorComparisonOfferScore,
  parseVendorComparisonEvent,
  ReviseVendorComparisonInputSchema,
  CreateVendorComparisonInputSchema,
} from "./vendor-comparison.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const COMPARISON_ID = "323e4567-e89b-12d3-a456-426614174000";
const RFQ_ID = "423e4567-e89b-12d3-a456-426614174000";
const SOURCING_REQUEST_ID = "523e4567-e89b-12d3-a456-426614174000";
const OFFER_ID = "623e4567-e89b-12d3-a456-426614174000";
const RESPONSE_ID = "723e4567-e89b-12d3-a456-426614174000";
const INVITATION_ID = "823e4567-e89b-12d3-a456-426614174000";
const VENDOR_MASTER_ID = "923e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "a23e4567-e89b-12d3-a456-426614174000";

const BASE_COMPARISON_ROW = {
  id: COMPARISON_ID,
  tenant_id: TENANT_ID,
  org_unit_id: null,
  rfq_id: RFQ_ID,
  sourcing_request_id: SOURCING_REQUEST_ID,
  version: 1,
  revised_from_id: null,
  comparison_currency: "IDR",
  basis_weight: 5000,
  basis_volume: null,
  basis_quantity: 1,
  criteria_snapshot: [{ key: "price", label: "Price", weight: 100 }],
  status: "draft",
  recommended_offer_id: null,
  recommended_reason: null,
  recommended_at: null,
  selected_offer_id: null,
  selection_reason: null,
  submitted_at: null,
  submitted_by: null,
  idempotency_key: "idem-1",
  record_version: 1,
  created_by: "tester",
  created_at: "2026-08-01T00:00:00.000Z",
  updated_at: "2026-08-01T00:00:00.000Z",
};

describe("parseVendorComparison", () => {
  test("maps every snake_case column to camelCase", () => {
    const parsed = parseVendorComparison(BASE_COMPARISON_ROW);
    assert.equal(parsed.id, COMPARISON_ID);
    assert.equal(parsed.rfqId, RFQ_ID);
    assert.equal(parsed.comparisonCurrency, "IDR");
    assert.equal(parsed.status, "draft");
  });

  test("parses criteria_snapshot into a typed array", () => {
    const parsed = parseVendorComparison(BASE_COMPARISON_ROW);
    assert.equal(parsed.criteriaSnapshot.length, 1);
    assert.equal(parsed.criteriaSnapshot[0]?.key, "price");
    assert.equal(parsed.criteriaSnapshot[0]?.weight, 100);
  });

  test("round-trips every status enum value", () => {
    for (const status of ["draft", "recommended", "submitted", "cancelled", "superseded"] as const) {
      const parsed = parseVendorComparison({ ...BASE_COMPARISON_ROW, status });
      assert.equal(parsed.status, status);
    }
  });
});

describe("parseVendorComparisonOffer", () => {
  const BASE_OFFER_ROW = {
    id: OFFER_ID,
    tenant_id: TENANT_ID,
    comparison_id: COMPARISON_ID,
    rfq_response_id: RESPONSE_ID,
    rfq_invitation_id: INVITATION_ID,
    vendor_master_id: VENDOR_MASTER_ID,
    rate_version_id: null,
    source_currency: "USD",
    source_total_amount: 1000,
    engine_computed_amount: null,
    engine_currency: null,
    engine_breakdown: null,
    normalized_amount: 15500000,
    normalization_lineage: { rate: 15500, sourceCurrency: "USD" },
    included: true,
    exclusion_reason: null,
    price_score: 100,
    non_price_score: null,
    composite_score: 100,
    rank: 1,
    record_version: 1,
    created_at: "2026-08-01T00:00:00.000Z",
    updated_at: "2026-08-01T00:00:00.000Z",
  };

  test("maps every snake_case column to camelCase, including cross-currency lineage", () => {
    const parsed = parseVendorComparisonOffer(BASE_OFFER_ROW);
    assert.equal(parsed.id, OFFER_ID);
    assert.equal(parsed.sourceCurrency, "USD");
    assert.equal(parsed.normalizedAmount, 15500000);
    assert.equal((parsed.normalizationLineage as Record<string, unknown>).rate, 15500);
  });

  test("an excluded offer requires a non-null exclusionReason shape to be representable", () => {
    const parsed = parseVendorComparisonOffer({ ...BASE_OFFER_ROW, included: false, exclusion_reason: "auto:fx_rate_missing", normalized_amount: null, rank: null });
    assert.equal(parsed.included, false);
    assert.equal(parsed.exclusionReason, "auto:fx_rate_missing");
    assert.equal(parsed.rank, null);
  });
});

describe("parseVendorComparisonOfferScore", () => {
  test("maps every snake_case column to camelCase", () => {
    const parsed = parseVendorComparisonOfferScore({
      id: "b23e4567-e89b-12d3-a456-426614174000",
      tenant_id: TENANT_ID,
      comparison_offer_id: OFFER_ID,
      criterion_key: "service_quality",
      criterion_weight: 20,
      score: 85,
      notes: "strong track record",
      scored_by: "reviewer",
      scored_at: "2026-08-01T00:00:00.000Z",
    });
    assert.equal(parsed.criterionKey, "service_quality");
    assert.equal(parsed.score, 85);
  });
});

describe("parseVendorComparisonEvent", () => {
  test("maps every snake_case column to camelCase", () => {
    const parsed = parseVendorComparisonEvent({
      id: "c23e4567-e89b-12d3-a456-426614174000",
      tenant_id: TENANT_ID,
      comparison_id: COMPARISON_ID,
      from_status: "draft",
      to_status: "recommended",
      reason: "lowest normalized cost",
      evidence_ref: OFFER_ID,
      actor_auth_user_id: ACTOR_ID,
      actor_label: "reviewer",
      occurred_at: "2026-08-01T00:00:00.000Z",
    });
    assert.equal(parsed.fromStatus, "draft");
    assert.equal(parsed.toStatus, "recommended");
  });
});

describe("CreateVendorComparisonInputSchema", () => {
  test("defaults basis and criteria fields to null when omitted", () => {
    const parsed = CreateVendorComparisonInputSchema.parse({
      tenantId: TENANT_ID,
      rfqId: RFQ_ID,
      comparisonCurrency: "IDR",
      idempotencyKey: "idem-create-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "reviewer",
    });
    assert.equal(parsed.basisWeight, null);
    assert.equal(parsed.criteria, null);
  });

  test("rejects an empty idempotencyKey", () => {
    assert.throws(() =>
      CreateVendorComparisonInputSchema.parse({
        tenantId: TENANT_ID,
        rfqId: RFQ_ID,
        comparisonCurrency: "IDR",
        idempotencyKey: "",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "reviewer",
      }),
    );
  });
});

describe("ReviseVendorComparisonInputSchema", () => {
  test("requires a non-empty reason", () => {
    assert.throws(() =>
      ReviseVendorComparisonInputSchema.parse({
        comparisonId: COMPARISON_ID,
        reason: "",
        idempotencyKey: "idem-revise-1",
        expectedVersion: 1,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "reviewer",
      }),
    );
  });

  test("accepts a valid revision payload", () => {
    const parsed = ReviseVendorComparisonInputSchema.parse({
      comparisonId: COMPARISON_ID,
      reason: "vendor B submitted a best-and-final offer",
      idempotencyKey: "idem-revise-2",
      expectedVersion: 1,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "reviewer",
    });
    assert.equal(parsed.reason, "vendor B submitted a best-and-final offer");
    assert.equal(parsed.expectedVersion, 1);
  });
});
