import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseAiQuotationSuggestion,
  parseAiQuotationSuggestionDetail,
  parseAiQuotationPromptContext,
  RecordAiQuotationSuggestionInputSchema,
  DismissAiQuotationSuggestionInputSchema,
  AcceptAiQuotationSuggestionAsDraftInputSchema,
  AcceptedQuotationLineSchema,
} from "./ai-quotation.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const OPPORTUNITY_ID = "323e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "423e4567-e89b-12d3-a456-426614174000";
const SUGGESTION_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const MARGIN_CALCULATION_ID = "723e4567-e89b-12d3-a456-426614174000";

describe("parseAiQuotationSuggestion", () => {
  test("round-trips a pending row", () => {
    const suggestion = parseAiQuotationSuggestion({
      id: SUGGESTION_ID,
      tenant_id: TENANT_ID,
      opportunity_id: OPPORTUNITY_ID,
      ai_governed_request_id: REQUEST_ID,
      status: "pending",
      accepted_quotation_id: null,
      dismiss_reason: null,
      requested_by_auth_user_id: ACTOR_ID,
      requested_by: "sales rep",
      reviewed_by_auth_user_id: null,
      reviewed_by: null,
      reviewed_at: null,
      created_at: "2026-08-21T00:00:00.000Z",
    });
    assert.equal(suggestion.status, "pending");
    assert.equal(suggestion.acceptedQuotationId, null);
  });

  test("rejects an accepted row missing accepted_quotation_id (accepted-shape invariant mirrored client-side)", () => {
    assert.throws(() =>
      parseAiQuotationSuggestion({
        id: SUGGESTION_ID,
        tenant_id: TENANT_ID,
        opportunity_id: OPPORTUNITY_ID,
        ai_governed_request_id: REQUEST_ID,
        status: "not-a-real-status",
        accepted_quotation_id: null,
        dismiss_reason: null,
        requested_by_auth_user_id: null,
        requested_by: null,
        reviewed_by_auth_user_id: null,
        reviewed_by: null,
        reviewed_at: null,
        created_at: "2026-08-21T00:00:00.000Z",
      }),
    );
  });
});

describe("parseAiQuotationSuggestionDetail", () => {
  test("round-trips a joined get/list row including the underlying governed request's own evidence", () => {
    const detail = parseAiQuotationSuggestionDetail({
      id: SUGGESTION_ID,
      tenant_id: TENANT_ID,
      opportunity_id: OPPORTUNITY_ID,
      ai_governed_request_id: REQUEST_ID,
      status: "accepted",
      accepted_quotation_id: "823e4567-e89b-12d3-a456-426614174000",
      dismiss_reason: null,
      requested_by: "sales rep",
      reviewed_by: "sales manager",
      reviewed_at: "2026-08-21T01:00:00.000Z",
      created_at: "2026-08-21T00:00:00.000Z",
      output_payload: { draftLines: [] },
      output_payload_masked: false,
      confidence_label: "high",
      model_version: "gpt-real-vision-2026-08",
      billed_amount: 0.021,
      request_status: "succeeded",
    });
    assert.equal(detail.confidenceLabel, "high");
    assert.equal(detail.requestStatus, "succeeded");
    assert.equal(detail.outputPayloadMasked, false);
  });

  test("Tier C fix: a masked row (actor lacks COM:View cost) nulls output_payload and flags output_payload_masked", () => {
    const detail = parseAiQuotationSuggestionDetail({
      id: SUGGESTION_ID,
      tenant_id: TENANT_ID,
      opportunity_id: OPPORTUNITY_ID,
      ai_governed_request_id: REQUEST_ID,
      status: "pending",
      accepted_quotation_id: null,
      dismiss_reason: null,
      requested_by: "sales rep",
      reviewed_by: null,
      reviewed_at: null,
      created_at: "2026-08-21T00:00:00.000Z",
      output_payload: null,
      output_payload_masked: true,
      confidence_label: "high",
      model_version: "gpt-real-vision-2026-08",
      billed_amount: 0.021,
      request_status: "succeeded",
    });
    assert.equal(detail.outputPayload, null);
    assert.equal(detail.outputPayloadMasked, true);
  });
});

describe("RecordAiQuotationSuggestionInputSchema", () => {
  test("requires a non-empty actorLabel", () => {
    assert.throws(() =>
      RecordAiQuotationSuggestionInputSchema.parse({
        tenantId: TENANT_ID,
        opportunityId: OPPORTUNITY_ID,
        aiGovernedRequestId: REQUEST_ID,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "",
      }),
    );
  });
});

describe("DismissAiQuotationSuggestionInputSchema", () => {
  test("requires a non-empty reason", () => {
    assert.throws(() =>
      DismissAiQuotationSuggestionInputSchema.parse({
        suggestionId: SUGGESTION_ID,
        reason: "",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "sales manager",
      }),
    );
  });
});

describe("AcceptedQuotationLineSchema", () => {
  test("requires a real margin_calculation_id -- never optional (design decision 3's own client-side mirror)", () => {
    assert.throws(() =>
      AcceptedQuotationLineSchema.parse({
        lineType: "service",
        description: "Ocean freight JKT-SIN",
        quantity: 1,
        unitPrice: 100,
      }),
    );
  });

  test("defaults discountPct/taxPct to 0", () => {
    const line = AcceptedQuotationLineSchema.parse({
      lineType: "service",
      description: "Ocean freight JKT-SIN",
      marginCalculationId: MARGIN_CALCULATION_ID,
      quantity: 1,
      unitPrice: 100,
    });
    assert.equal(line.discountPct, 0);
    assert.equal(line.taxPct, 0);
  });
});

describe("AcceptAiQuotationSuggestionAsDraftInputSchema", () => {
  test("requires at least one accepted line", () => {
    assert.throws(() =>
      AcceptAiQuotationSuggestionAsDraftInputSchema.parse({
        suggestionId: SUGGESTION_ID,
        currency: "USD",
        validityTo: "2026-09-21T00:00:00.000Z",
        acceptedLines: [],
        actorAuthUserId: ACTOR_ID,
        actorLabel: "sales manager",
      }),
    );
  });

  test("rejects a lowercase/malformed currency code", () => {
    assert.throws(() =>
      AcceptAiQuotationSuggestionAsDraftInputSchema.parse({
        suggestionId: SUGGESTION_ID,
        currency: "usd",
        validityTo: "2026-09-21T00:00:00.000Z",
        acceptedLines: [{ lineType: "service", description: "Ocean freight", marginCalculationId: MARGIN_CALCULATION_ID, quantity: 1, unitPrice: 100 }],
        actorAuthUserId: ACTOR_ID,
        actorLabel: "sales manager",
      }),
    );
  });
});

describe("parseAiQuotationPromptContext", () => {
  test("Tier C fix: returns null for zero rows (opportunity not found/not accessible)", () => {
    assert.equal(parseAiQuotationPromptContext([]), null);
  });

  test("a header row with no margin calculations yet produces an empty marginSources array, not a fabricated one", () => {
    const context = parseAiQuotationPromptContext([
      {
        opportunity_name: "Contoso freight lane",
        opportunity_stage: "ready_for_costing",
        opportunity_value_amount: 5000,
        opportunity_value_currency: "USD",
        opportunity_requirements: { origin: "JKT" },
        costing_request_id: null,
        margin_calculation_id: null,
        rate_selection_id: null,
        rule_version_id: null,
        sell_amount: null,
        sell_currency: null,
        margin_pct: null,
      },
    ]);
    assert.equal(context?.costingRequestId, null);
    assert.deepEqual(context?.marginSources, []);
  });

  test("real, current margin sources round-trip with numeric coercion (Postgres numeric arrives as a string over the wire)", () => {
    const context = parseAiQuotationPromptContext([
      {
        opportunity_name: "Contoso freight lane",
        opportunity_stage: "ready_for_costing",
        opportunity_value_amount: "5000.00",
        opportunity_value_currency: "USD",
        opportunity_requirements: {},
        costing_request_id: "823e4567-e89b-12d3-a456-426614174000",
        margin_calculation_id: MARGIN_CALCULATION_ID,
        rate_selection_id: "923e4567-e89b-12d3-a456-426614174000",
        rule_version_id: "a23e4567-e89b-12d3-a456-426614174000",
        sell_amount: "19999999.99",
        sell_currency: "IDR",
        margin_pct: "38.27",
      },
    ]);
    assert.equal(context?.opportunityValueAmount, 5000);
    assert.equal(context?.marginSources.length, 1);
    assert.equal(context?.marginSources[0]?.sellAmount, 19999999.99);
    assert.equal(context?.marginSources[0]?.marginPct, 38.27);
  });

  test("multiple current margin calculations for the same opportunity all round-trip", () => {
    const rowBase = {
      opportunity_name: "Contoso freight lane",
      opportunity_stage: "ready_for_costing",
      opportunity_value_amount: 5000,
      opportunity_value_currency: "USD",
      opportunity_requirements: {},
      costing_request_id: "823e4567-e89b-12d3-a456-426614174000",
      sell_currency: "USD",
    };
    const context = parseAiQuotationPromptContext([
      { ...rowBase, margin_calculation_id: MARGIN_CALCULATION_ID, rate_selection_id: "923e4567-e89b-12d3-a456-426614174000", rule_version_id: "a23e4567-e89b-12d3-a456-426614174000", sell_amount: 500, margin_pct: 20 },
      { ...rowBase, margin_calculation_id: "b23e4567-e89b-12d3-a456-426614174000", rate_selection_id: "c23e4567-e89b-12d3-a456-426614174000", rule_version_id: "d23e4567-e89b-12d3-a456-426614174000", sell_amount: 800, margin_pct: 25 },
    ]);
    assert.equal(context?.marginSources.length, 2);
  });
});
