import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createVendorProfileDraft,
  submitVendorProfileForReview,
  decideVendorProfileReview,
  suspendVendorProfile,
  addVendorContact,
  flagVendorDuplicateCandidate,
  createVendorIntakeToken,
  redeemVendorIntakeToken,
  submitVendorProfileSelfRegistration,
  resolveVendorSelfRegistrationTarget,
  VendorProfileMutationError,
  type VendorProfileMutationRpcClient,
} from "./vendor-profile.ts";

const MASTER_RECORD_ID = "223e4567-e89b-12d3-a456-426614174000";
const TENANT_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: VendorProfileMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as VendorProfileMutationRpcClient;
  return { client, calls };
}

const PROFILE_ROW = {
  master_record_id: MASTER_RECORD_ID,
  tenant_id: TENANT_ID,
  legal_name: "PT Contoso Logistik",
  trade_name: null,
  legal_entity_type: null,
  business_registration_number: null,
  vendor_category: null,
  payment_term_days: null,
  intake_source: "staff_created",
  lifecycle_status: "draft",
  revision_reason: null,
  suspend_reason: null,
  blacklist_reason: null,
  blacklist_evidence_ref: null,
  record_version: 1,
  created_by: "staff",
  created_at: "2026-08-05T00:00:00.000Z",
  updated_at: "2026-08-05T00:00:00.000Z",
};

describe("createVendorProfileDraft", () => {
  test("calls create_vendor_profile_draft with mapped snake_case args and parses the response", async () => {
    const { client, calls } = fakeRpcClient({ data: [PROFILE_ROW], error: null });
    const result = await createVendorProfileDraft(client, {
      tenantId: TENANT_ID,
      legalName: "PT Contoso Logistik",
      tradeName: null,
      legalEntityType: null,
      businessRegistrationNumber: null,
      vendorCategory: null,
      paymentTermDays: null,
      intakeSource: "staff_created",
      idempotencyKey: "idem-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "staff",
    });
    assert.equal(calls[0]?.fn, "create_vendor_profile_draft");
    assert.equal(calls[0]?.args.p_legal_name, "PT Contoso Logistik");
    assert.equal(result.lifecycleStatus, "draft");
  });

  test("classifies a known error prefix (idempotency_key_conflict)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "idempotency_key_conflict: idempotency key idem-1 was already used for a different vendor registration" } });
    await assert.rejects(
      () =>
        createVendorProfileDraft(client, {
          tenantId: TENANT_ID,
          legalName: "PT Contoso Logistik",
          tradeName: null,
          legalEntityType: null,
          businessRegistrationNumber: null,
          vendorCategory: null,
          paymentTermDays: null,
          intakeSource: "staff_created",
          idempotencyKey: "idem-1",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "staff",
        }),
      (error: unknown) => error instanceof VendorProfileMutationError && error.code === "idempotency_key_conflict",
    );
  });

  test("classifies an unrecognized error prefix as mutation_failed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "some_never_seeded_prefix: boom" } });
    await assert.rejects(
      () =>
        createVendorProfileDraft(client, {
          tenantId: TENANT_ID,
          legalName: "PT Contoso Logistik",
          tradeName: null,
          legalEntityType: null,
          businessRegistrationNumber: null,
          vendorCategory: null,
          paymentTermDays: null,
          intakeSource: "staff_created",
          idempotencyKey: null,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "staff",
        }),
      (error: unknown) => error instanceof VendorProfileMutationError && error.code === "mutation_failed",
    );
  });
});

describe("submitVendorProfileForReview", () => {
  test("classifies stale_version", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "stale_version: vendor profile expected version 1 but found 2" } });
    await assert.rejects(
      () => submitVendorProfileForReview(client, { masterRecordId: MASTER_RECORD_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "staff" }),
      (error: unknown) => error instanceof VendorProfileMutationError && error.code === "stale_version",
    );
  });

  test("classifies missing_required_contact", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "missing_required_contact: vendor profile has no active contact" } });
    await assert.rejects(
      () => submitVendorProfileForReview(client, { masterRecordId: MASTER_RECORD_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "staff" }),
      (error: unknown) => error instanceof VendorProfileMutationError && error.code === "missing_required_contact",
    );
  });
});

describe("decideVendorProfileReview", () => {
  test("sends decision/reason through to p_decision/p_reason", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...PROFILE_ROW, lifecycle_status: "draft", revision_reason: "missing docs" }], error: null });
    const result = await decideVendorProfileReview(client, {
      masterRecordId: MASTER_RECORD_ID,
      expectedVersion: 3,
      decision: "reject",
      reason: "missing docs",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "reviewer",
    });
    assert.equal(calls[0]?.args.p_decision, "reject");
    assert.equal(calls[0]?.args.p_reason, "missing docs");
    assert.equal(result.revisionReason, "missing docs");
  });
});

describe("suspendVendorProfile", () => {
  test("rejects an empty reason at the schema layer before ever calling the RPC", async () => {
    const { client, calls } = fakeRpcClient({ data: [PROFILE_ROW], error: null });
    await assert.rejects(() => suspendVendorProfile(client, { masterRecordId: MASTER_RECORD_ID, expectedVersion: 1, reason: "", actorAuthUserId: ACTOR_ID, actorLabel: "manager" }));
    assert.equal(calls.length, 0);
  });
});

describe("addVendorContact", () => {
  test("classifies vendor_profile_not_draft", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "vendor_profile_not_draft: vendor profile is submitted -- child records may only be edited while draft" } });
    await assert.rejects(
      () => addVendorContact(client, { masterRecordId: MASTER_RECORD_ID, name: "Jane", title: null, email: null, phone: null, isPrimary: true, actorAuthUserId: ACTOR_ID, actorLabel: "staff" }),
      (error: unknown) => error instanceof VendorProfileMutationError && error.code === "vendor_profile_not_draft",
    );
  });
});

describe("flagVendorDuplicateCandidate", () => {
  test("maps a pending candidate response", async () => {
    const { client } = fakeRpcClient({
      data: [
        {
          id: MASTER_RECORD_ID,
          source_master_record_id: MASTER_RECORD_ID,
          candidate_master_record_id: TENANT_ID,
          similarity_basis: "trigram legal_name similarity",
          similarity_score: 0.7,
          decision: "pending",
          decided_by: null,
          decided_at: null,
          decided_reason: null,
          record_version: 1,
          created_at: "2026-08-05T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const candidate = await flagVendorDuplicateCandidate(client, {
      sourceMasterRecordId: MASTER_RECORD_ID,
      candidateMasterRecordId: TENANT_ID,
      similarityBasis: "trigram legal_name similarity",
      similarityScore: 0.7,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "staff",
    });
    assert.equal(candidate.decision, "pending");
  });
});

describe("createVendorIntakeToken", () => {
  test("returns a raw_token on a true first issuance", async () => {
    const { client } = fakeRpcClient({ data: [{ token_id: MASTER_RECORD_ID, raw_token: "abc123", expires_at: "2026-08-12T00:00:00.000Z", intended_email: "invitee@newvendor.test" }], error: null });
    const result = await createVendorIntakeToken(client, { tenantId: TENANT_ID, intendedEmail: "invitee@newvendor.test", validityDays: 7, idempotencyKey: null, actorAuthUserId: ACTOR_ID, actorLabel: "staff" });
    assert.equal(result.rawToken, "abc123");
  });
});

describe("redeemVendorIntakeToken (anonymous)", () => {
  test("maps an ok result with no actor/session fields in the input shape", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ submit_status: "ok", master_record_id: MASTER_RECORD_ID }], error: null });
    const result = await redeemVendorIntakeToken(client, {
      rawToken: "raw-token-value",
      clientKey: "client-key-1",
      legalName: "PT Invitee Logistics",
      tradeName: null,
      legalEntityType: null,
      businessRegistrationNumber: null,
      vendorCategory: null,
      paymentTermDays: null,
      contactName: null,
      contactEmail: null,
      contactPhone: null,
    });
    assert.equal(calls[0]?.fn, "redeem_vendor_intake_token_and_submit");
    assert.equal(result.submitStatus, "ok");
    assert.equal(result.masterRecordId, MASTER_RECORD_ID);
  });

  test("maps a rate_limited result with a null master_record_id", async () => {
    const { client } = fakeRpcClient({ data: [{ submit_status: "rate_limited", master_record_id: null }], error: null });
    const result = await redeemVendorIntakeToken(client, {
      rawToken: "raw-token-value",
      clientKey: "client-key-1",
      legalName: "PT Invitee Logistics",
      tradeName: null,
      legalEntityType: null,
      businessRegistrationNumber: null,
      vendorCategory: null,
      paymentTermDays: null,
      contactName: null,
      contactEmail: null,
      contactPhone: null,
    });
    assert.equal(result.submitStatus, "rate_limited");
    assert.equal(result.masterRecordId, null);
  });
});

describe("submitVendorProfileSelfRegistration (anonymous)", () => {
  test("maps a disabled result (self-registration off by default)", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ submit_status: "disabled", master_record_id: null }], error: null });
    const result = await submitVendorProfileSelfRegistration(client, {
      tenantId: TENANT_ID,
      clientKey: "client-key-2",
      legalName: "PT Self Reg",
      tradeName: null,
      legalEntityType: null,
      businessRegistrationNumber: null,
      vendorCategory: null,
      paymentTermDays: null,
      contactName: null,
      contactEmail: null,
      contactPhone: null,
      idempotencyKey: null,
    });
    assert.equal(calls[0]?.fn, "submit_vendor_profile_self_registration");
    assert.equal(result.submitStatus, "disabled");
  });
});

describe("resolveVendorSelfRegistrationTarget (anonymous)", () => {
  test("maps an enabled target", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ tenant_id: TENANT_ID, self_registration_enabled: true }], error: null });
    const result = await resolveVendorSelfRegistrationTarget(client, "acme");
    assert.equal(calls[0]?.fn, "resolve_vendor_self_registration_target");
    assert.deepEqual(calls[0]?.args, { p_tenant_slug: "acme" });
    assert.equal(result.tenantId, TENANT_ID);
    assert.equal(result.selfRegistrationEnabled, true);
  });

  test("maps the uniform not-available result for a nonexistent/inactive/disabled tenant", async () => {
    const { client } = fakeRpcClient({ data: [{ tenant_id: null, self_registration_enabled: false }], error: null });
    const result = await resolveVendorSelfRegistrationTarget(client, "does-not-exist");
    assert.equal(result.tenantId, null);
    assert.equal(result.selfRegistrationEnabled, false);
  });
});
