import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  CreateOpportunityInputSchema,
  UpdateOpportunityInputSchema,
  TransitionOpportunityStageInputSchema,
  toRequirementsJson,
  parseOpportunity,
  parseOpportunityStageHistoryEntry,
  parseCostingReadiness,
} from "./opportunity.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const OPPORTUNITY_ID = "323e4567-e89b-12d3-a456-426614174000";
const PROSPECT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

describe("CreateOpportunityInputSchema", () => {
  test("applies defaults for omitted optional fields", () => {
    const parsed = CreateOpportunityInputSchema.parse({
      tenantId: TENANT_ID,
      prospectId: PROSPECT_ID,
      name: "Contoso freight lane",
      actorAuthUserId: ACTOR_ID,
      createdBy: "tester",
    });
    assert.equal(parsed.requirements, null);
    assert.equal(parsed.ownerUserId, null);
  });
});

describe("UpdateOpportunityInputSchema", () => {
  test("rejects a malformed currency code", () => {
    assert.throws(() =>
      UpdateOpportunityInputSchema.parse({
        opportunityId: OPPORTUNITY_ID,
        expectedVersion: 1,
        valueCurrency: "idr",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "tester",
      }),
    );
  });
});

describe("TransitionOpportunityStageInputSchema", () => {
  test("rejects an unknown stage", () => {
    assert.throws(() =>
      TransitionOpportunityStageInputSchema.parse({
        opportunityId: OPPORTUNITY_ID,
        expectedVersion: 1,
        newStage: "teleported",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "tester",
      }),
    );
  });
});

describe("toRequirementsJson", () => {
  test("maps camelCase fields to the snake_case keys the DB functions read", () => {
    const json = toRequirementsJson({ serviceType: "freight_forwarding", cargoDescription: "General cargo" });
    assert.equal(json?.service_type, "freight_forwarding");
    assert.equal(json?.cargo_description, "General cargo");
    assert.equal(json?.origin, null);
  });

  test("returns null for a null/undefined input", () => {
    assert.equal(toRequirementsJson(null), null);
    assert.equal(toRequirementsJson(undefined), null);
  });
});

describe("parseOpportunity", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const opportunity = parseOpportunity({
      id: OPPORTUNITY_ID,
      tenant_id: TENANT_ID,
      prospect_id: PROSPECT_ID,
      account_ref: null,
      name: "Contoso freight lane",
      stage: "qualifying",
      probability: 10,
      value_amount: null,
      value_currency: null,
      requirements: { service_type: "freight_forwarding" },
      next_action: null,
      next_action_due_at: null,
      close_reason: null,
      cloned_from_id: null,
      owner_user_id: ACTOR_ID,
      org_unit_id: null,
      record_version: 1,
      created_by: "tester",
      created_at: "2026-07-23T00:00:00.000Z",
      updated_at: "2026-07-23T00:00:00.000Z",
    });
    assert.equal(opportunity.stage, "qualifying");
    assert.equal(opportunity.requirements.serviceType, "freight_forwarding");
  });

  test("coerces a string numeric value_amount", () => {
    const opportunity = parseOpportunity({
      id: OPPORTUNITY_ID,
      tenant_id: TENANT_ID,
      prospect_id: PROSPECT_ID,
      account_ref: null,
      name: "Contoso freight lane",
      stage: "qualifying",
      probability: 10,
      value_amount: "15000000.00",
      value_currency: "IDR",
      value_masked: false,
      requirements: {},
      next_action: null,
      next_action_due_at: null,
      close_reason: null,
      cloned_from_id: null,
      owner_user_id: ACTOR_ID,
      org_unit_id: null,
      record_version: 1,
      created_by: "tester",
      created_at: "2026-07-23T00:00:00.000Z",
      updated_at: "2026-07-23T00:00:00.000Z",
    });
    assert.equal(opportunity.valueAmount, 15000000);
    assert.equal(opportunity.valueMasked, false);
  });
});

describe("parseOpportunityStageHistoryEntry", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const entry = parseOpportunityStageHistoryEntry({
      id: "623e4567-e89b-12d3-a456-426614174000",
      tenant_id: TENANT_ID,
      opportunity_id: OPPORTUNITY_ID,
      from_stage: "qualifying",
      to_stage: "requirements_gathering",
      probability: 30,
      reason: null,
      changed_by: "tester",
      changed_at: "2026-07-23T00:00:00.000Z",
    });
    assert.equal(entry.fromStage, "qualifying");
    assert.equal(entry.toStage, "requirements_gathering");
  });
});

describe("parseCostingReadiness", () => {
  test("maps a not-ready result with missing fields", () => {
    const readiness = parseCostingReadiness({ ready: false, missing: ["cargo_description", "origin"] });
    assert.equal(readiness.ready, false);
    assert.deepEqual(readiness.missing, ["cargo_description", "origin"]);
  });
});
