import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  convertLeadToProspect,
  linkLeadToExistingProspect,
  disqualifyProspect,
  archiveProspect,
  mergeProspects,
  ProspectMutationError,
  type ProspectMutationRpcClient,
} from "./prospect.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const LEAD_ID = "323e4567-e89b-12d3-a456-426614174000";
const PROSPECT_ID = "423e4567-e89b-12d3-a456-426614174000";
const SURVIVOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

const VALID_PROSPECT_ROW = {
  id: PROSPECT_ID,
  tenant_id: TENANT_ID,
  lead_id: LEAD_ID,
  legal_name: "Contoso Ltd",
  trade_name: null,
  tax_id: null,
  billing_address: {},
  contact_name: "Jane Doe",
  contact_email: "jane@contoso.test",
  contact_phone: null,
  status: "active",
  disqualify_reason: null,
  owner_user_id: ACTOR_ID,
  org_unit_id: null,
  merged_into_id: null,
  merged_at: null,
  merged_by: null,
  record_version: 1,
  created_by: "tester",
  created_at: "2026-07-23T00:00:00.000Z",
  updated_at: "2026-07-23T00:00:00.000Z",
};

function fakeClient(response: { data: unknown; error: { message: string } | null }): ProspectMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const fake = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  };
  return Object.assign(fake as unknown as ProspectMutationRpcClient, { calls });
}

describe("convertLeadToProspect", () => {
  test("calls convert_lead_to_prospect with the exact snake_case params and defaults applied", async () => {
    const client = fakeClient({ data: VALID_PROSPECT_ROW, error: null });
    await convertLeadToProspect(client, { leadId: LEAD_ID, legalName: "Contoso Ltd", actorAuthUserId: ACTOR_ID, createdBy: "tester" });

    assert.deepEqual(client.calls[0]?.args, {
      p_lead_id: LEAD_ID,
      p_legal_name: "Contoso Ltd",
      p_trade_name: null,
      p_tax_id: null,
      p_billing_address: {},
      p_actor_auth_user_id: ACTOR_ID,
      p_created_by: "tester",
    });
  });

  test("wraps an invalid_transition error (lead not qualified)", async () => {
    const client = fakeClient({ data: null, error: { message: "invalid_transition: lead x is new and cannot convert to a prospect (must be qualified)" } });
    await assert.rejects(
      () => convertLeadToProspect(client, { leadId: LEAD_ID, legalName: "Contoso Ltd", actorAuthUserId: ACTOR_ID, createdBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof ProspectMutationError);
        assert.equal(err.code, "invalid_transition");
        return true;
      },
    );
  });
});

describe("linkLeadToExistingProspect", () => {
  test("calls link_lead_to_existing_prospect with the exact snake_case params", async () => {
    const client = fakeClient({ data: VALID_PROSPECT_ROW, error: null });
    await linkLeadToExistingProspect(client, { leadId: LEAD_ID, prospectId: PROSPECT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });
    assert.deepEqual(client.calls[0]?.args, {
      p_lead_id: LEAD_ID,
      p_prospect_id: PROSPECT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "tester",
    });
  });

  test("wraps a cross_tenant_link_denied error", async () => {
    const client = fakeClient({ data: null, error: { message: "cross_tenant_link_denied: lead and prospect belong to different tenants" } });
    await assert.rejects(
      () => linkLeadToExistingProspect(client, { leadId: LEAD_ID, prospectId: PROSPECT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof ProspectMutationError);
        assert.equal(err.code, "cross_tenant_link_denied");
        return true;
      },
    );
  });
});

describe("disqualifyProspect", () => {
  test("calls disqualify_prospect with the exact snake_case params", async () => {
    const client = fakeClient({ data: { ...VALID_PROSPECT_ROW, status: "disqualified", disqualify_reason: "No budget" }, error: null });
    await disqualifyProspect(client, { prospectId: PROSPECT_ID, expectedVersion: 1, reason: "No budget", actorAuthUserId: ACTOR_ID, actorLabel: "tester" });
    assert.deepEqual(client.calls[0]?.args, {
      p_prospect_id: PROSPECT_ID,
      p_expected_version: 1,
      p_reason: "No budget",
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "tester",
    });
  });

  test("rejects an empty reason before ever calling the RPC", async () => {
    const client = fakeClient({ data: VALID_PROSPECT_ROW, error: null });
    await assert.rejects(() => disqualifyProspect(client, { prospectId: PROSPECT_ID, expectedVersion: 1, reason: "", actorAuthUserId: ACTOR_ID, actorLabel: "tester" }));
    assert.equal(client.calls.length, 0);
  });
});

describe("archiveProspect", () => {
  test("calls archive_prospect with the exact snake_case params", async () => {
    const client = fakeClient({ data: { ...VALID_PROSPECT_ROW, status: "archived" }, error: null });
    const prospect = await archiveProspect(client, { prospectId: PROSPECT_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });
    assert.equal(prospect.status, "archived");
  });

  test("wraps a stale_version error", async () => {
    const client = fakeClient({ data: null, error: { message: "stale_version: prospect x expected version 1 but found 2" } });
    await assert.rejects(
      () => archiveProspect(client, { prospectId: PROSPECT_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof ProspectMutationError);
        assert.equal(err.code, "stale_version");
        return true;
      },
    );
  });
});

describe("mergeProspects", () => {
  test("calls merge_prospects with the exact snake_case params", async () => {
    const survivorRow = { ...VALID_PROSPECT_ROW, id: SURVIVOR_ID };
    const client = fakeClient({ data: survivorRow, error: null });
    const prospect = await mergeProspects(client, { survivorProspectId: SURVIVOR_ID, duplicateProspectId: PROSPECT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.deepEqual(client.calls[0]?.args, {
      p_survivor_prospect_id: SURVIVOR_ID,
      p_duplicate_prospect_id: PROSPECT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "tester",
    });
    assert.equal(prospect.id, SURVIVOR_ID);
  });

  test("wraps a cross_tenant_merge_denied error", async () => {
    const client = fakeClient({ data: null, error: { message: "cross_tenant_merge_denied: survivor and duplicate belong to different tenants" } });
    await assert.rejects(
      () => mergeProspects(client, { survivorProspectId: SURVIVOR_ID, duplicateProspectId: PROSPECT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof ProspectMutationError);
        assert.equal(err.code, "cross_tenant_merge_denied");
        return true;
      },
    );
  });
});
