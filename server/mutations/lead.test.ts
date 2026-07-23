import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  captureLead,
  scoreLead,
  assignLead,
  qualifyLead,
  disqualifyLead,
  mergeLeads,
  LeadMutationError,
  type LeadMutationRpcClient,
} from "./lead.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const LEAD_ID = "323e4567-e89b-12d3-a456-426614174000";
const SURVIVOR_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

const VALID_LEAD_ROW = {
  id: LEAD_ID,
  tenant_id: TENANT_ID,
  source: "manual",
  external_reference: null,
  company_name: "Contoso Ltd",
  contact_name: "Jane Doe",
  email: "jane@contoso.test",
  phone: null,
  duplicate_fingerprint: "abc123",
  status: "new",
  disqualify_reason: null,
  score: 20,
  score_explanation: { version: 1, rules: [{ rule: "has_email", points: 20 }] },
  score_version: 1,
  owner_user_id: ACTOR_ID,
  org_unit_id: null,
  assigned_at: null,
  assigned_by: null,
  qualified_at: null,
  disqualified_at: null,
  merged_into_id: null,
  merged_at: null,
  merged_by: null,
  converted_at: null,
  last_activity_at: "2026-07-23T00:00:00.000Z",
  record_version: 1,
  created_by: "tester",
  created_at: "2026-07-23T00:00:00.000Z",
  updated_at: "2026-07-23T00:00:00.000Z",
};

function fakeClient(response: { data: unknown; error: { message: string } | null }): LeadMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const fake = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  };
  return Object.assign(fake as unknown as LeadMutationRpcClient, { calls });
}

describe("captureLead", () => {
  test("calls capture_lead with the exact snake_case params and defaults applied", async () => {
    const client = fakeClient({ data: VALID_LEAD_ROW, error: null });
    await captureLead(client, {
      tenantId: TENANT_ID,
      source: "manual",
      contactName: "Jane Doe",
      email: "jane@contoso.test",
      actorAuthUserId: ACTOR_ID,
      createdBy: "tester",
    });

    assert.deepEqual(client.calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_source: "manual",
      p_external_reference: null,
      p_company_name: null,
      p_contact_name: "Jane Doe",
      p_email: "jane@contoso.test",
      p_phone: null,
      p_owner_user_id: null,
      p_org_unit_id: null,
      p_actor_auth_user_id: ACTOR_ID,
      p_created_by: "tester",
    });
  });

  test("wraps an insufficient_authority error (lacking COM:Create)", async () => {
    const client = fakeClient({ data: null, error: { message: "insufficient_authority: identity x lacks COM:Create" } });
    await assert.rejects(
      () => captureLead(client, { tenantId: TENANT_ID, source: "manual", contactName: "Jane Doe", email: "jane@contoso.test", actorAuthUserId: ACTOR_ID, createdBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof LeadMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });

  test("rejects a malformed email before ever calling the RPC", async () => {
    const client = fakeClient({ data: VALID_LEAD_ROW, error: null });
    await assert.rejects(() =>
      captureLead(client, { tenantId: TENANT_ID, source: "manual", contactName: "Jane Doe", email: "not-an-email", actorAuthUserId: ACTOR_ID, createdBy: "tester" }),
    );
    assert.equal(client.calls.length, 0);
  });
});

describe("scoreLead", () => {
  test("calls score_lead with the exact snake_case params", async () => {
    const client = fakeClient({ data: VALID_LEAD_ROW, error: null });
    await scoreLead(client, { leadId: LEAD_ID, actorAuthUserId: ACTOR_ID });
    assert.deepEqual(client.calls[0]?.args, { p_lead_id: LEAD_ID, p_actor_auth_user_id: ACTOR_ID });
  });
});

describe("assignLead", () => {
  test("calls assign_lead with the exact snake_case params", async () => {
    const client = fakeClient({ data: { ...VALID_LEAD_ROW, record_version: 2 }, error: null });
    const lead = await assignLead(client, {
      leadId: LEAD_ID,
      expectedVersion: 1,
      newOwnerUserId: ACTOR_ID,
      newOrgUnitId: null,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });

    assert.deepEqual(client.calls[0]?.args, {
      p_lead_id: LEAD_ID,
      p_expected_version: 1,
      p_new_owner_user_id: ACTOR_ID,
      p_new_org_unit_id: null,
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "tester",
    });
    assert.equal(lead.recordVersion, 2);
  });

  test("wraps a stale_version error", async () => {
    const client = fakeClient({ data: null, error: { message: "stale_version: lead x expected version 1 but found 2" } });
    await assert.rejects(
      () => assignLead(client, { leadId: LEAD_ID, expectedVersion: 1, newOwnerUserId: ACTOR_ID, newOrgUnitId: null, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof LeadMutationError);
        assert.equal(err.code, "stale_version");
        return true;
      },
    );
  });
});

describe("qualifyLead", () => {
  test("calls qualify_lead with the exact snake_case params", async () => {
    const client = fakeClient({ data: { ...VALID_LEAD_ROW, status: "qualified" }, error: null });
    const lead = await qualifyLead(client, { leadId: LEAD_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });
    assert.equal(lead.status, "qualified");
  });

  test("wraps an invalid_transition error", async () => {
    const client = fakeClient({ data: null, error: { message: "invalid_transition: lead x is disqualified and cannot become qualified" } });
    await assert.rejects(
      () => qualifyLead(client, { leadId: LEAD_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof LeadMutationError);
        assert.equal(err.code, "invalid_transition");
        return true;
      },
    );
  });
});

describe("disqualifyLead", () => {
  test("calls disqualify_lead with the exact snake_case params", async () => {
    const client = fakeClient({ data: { ...VALID_LEAD_ROW, status: "disqualified", disqualify_reason: "Budget frozen" }, error: null });
    await disqualifyLead(client, { leadId: LEAD_ID, expectedVersion: 1, reason: "Budget frozen", actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.deepEqual(client.calls[0]?.args, {
      p_lead_id: LEAD_ID,
      p_expected_version: 1,
      p_reason: "Budget frozen",
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "tester",
    });
  });

  test("rejects an empty reason before ever calling the RPC", async () => {
    const client = fakeClient({ data: VALID_LEAD_ROW, error: null });
    await assert.rejects(() => disqualifyLead(client, { leadId: LEAD_ID, expectedVersion: 1, reason: "", actorAuthUserId: ACTOR_ID, actorLabel: "tester" }));
    assert.equal(client.calls.length, 0);
  });
});

describe("mergeLeads", () => {
  test("calls merge_leads with the exact snake_case params", async () => {
    const survivorRow = { ...VALID_LEAD_ROW, id: SURVIVOR_ID };
    const client = fakeClient({ data: survivorRow, error: null });
    const lead = await mergeLeads(client, { survivorLeadId: SURVIVOR_ID, duplicateLeadId: LEAD_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.deepEqual(client.calls[0]?.args, {
      p_survivor_lead_id: SURVIVOR_ID,
      p_duplicate_lead_id: LEAD_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "tester",
    });
    assert.equal(lead.id, SURVIVOR_ID);
  });

  test("wraps a cross_tenant_merge_denied error", async () => {
    const client = fakeClient({ data: null, error: { message: "cross_tenant_merge_denied: survivor and duplicate belong to different tenants" } });
    await assert.rejects(
      () => mergeLeads(client, { survivorLeadId: SURVIVOR_ID, duplicateLeadId: LEAD_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof LeadMutationError);
        assert.equal(err.code, "cross_tenant_merge_denied");
        return true;
      },
    );
  });
});
