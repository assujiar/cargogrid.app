import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { createOpportunity, transitionOpportunityStage, cloneOpportunity, OpportunityMutationError, type OpportunityMutationRpcClient } from "./opportunity.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const OPPORTUNITY_ID = "323e4567-e89b-12d3-a456-426614174000";
const PROSPECT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

const VALID_OPPORTUNITY_ROW = {
  id: OPPORTUNITY_ID,
  tenant_id: TENANT_ID,
  prospect_id: PROSPECT_ID,
  account_ref: null,
  name: "Contoso freight lane",
  stage: "qualifying",
  probability: 10,
  value_amount: null,
  value_currency: null,
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
};

describe("createOpportunity", () => {
  test("calls create_opportunity with the exact snake_case params, mapping requirements to snake_case keys", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = {
      async rpc(fn: string, args: Record<string, unknown>) {
        calls.push({ fn, args });
        return { data: VALID_OPPORTUNITY_ROW, error: null };
      },
    } as unknown as OpportunityMutationRpcClient;

    const opportunity = await createOpportunity(client, {
      tenantId: TENANT_ID,
      prospectId: PROSPECT_ID,
      name: "Contoso freight lane",
      requirements: { serviceType: "freight_forwarding" },
      actorAuthUserId: ACTOR_ID,
      createdBy: "tester",
    });

    assert.equal(calls[0]?.fn, "create_opportunity");
    assert.deepEqual((calls[0]?.args.p_requirements as Record<string, unknown>).service_type, "freight_forwarding");
    assert.equal(opportunity.stage, "qualifying");
  });
});

describe("transitionOpportunityStage", () => {
  test("classifies reason_required", async () => {
    const client = {
      async rpc() {
        return { data: null, error: { message: "reason_required: closing an opportunity as lost requires a non-empty reason" } };
      },
    } as unknown as OpportunityMutationRpcClient;

    await assert.rejects(
      () =>
        transitionOpportunityStage(client, {
          opportunityId: OPPORTUNITY_ID,
          expectedVersion: 1,
          newStage: "lost",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "tester",
        }),
      (err: unknown) => {
        assert.ok(err instanceof OpportunityMutationError);
        assert.equal((err as OpportunityMutationError).code, "reason_required");
        return true;
      },
    );
  });

  test("classifies an unrecognized error message as mutation_failed", async () => {
    const client = {
      async rpc() {
        return { data: null, error: { message: "some unexpected database error" } };
      },
    } as unknown as OpportunityMutationRpcClient;

    await assert.rejects(
      () =>
        transitionOpportunityStage(client, {
          opportunityId: OPPORTUNITY_ID,
          expectedVersion: 1,
          newStage: "won",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "tester",
        }),
      (err: unknown) => {
        assert.ok(err instanceof OpportunityMutationError);
        assert.equal((err as OpportunityMutationError).code, "mutation_failed");
        return true;
      },
    );
  });
});

describe("cloneOpportunity", () => {
  test("calls clone_opportunity with the exact snake_case params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = {
      async rpc(fn: string, args: Record<string, unknown>) {
        calls.push({ fn, args });
        return { data: { ...VALID_OPPORTUNITY_ROW, cloned_from_id: OPPORTUNITY_ID }, error: null };
      },
    } as unknown as OpportunityMutationRpcClient;

    const clone = await cloneOpportunity(client, { opportunityId: OPPORTUNITY_ID, name: "Renewal", actorAuthUserId: ACTOR_ID, createdBy: "tester" });
    assert.equal(calls[0]?.fn, "clone_opportunity");
    assert.equal(clone.clonedFromId, OPPORTUNITY_ID);
  });
});
