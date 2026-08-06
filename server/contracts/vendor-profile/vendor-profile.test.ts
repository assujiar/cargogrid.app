import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseVendorProfile,
  parseVendorProfileMutationResult,
  parseVendorProfileListRow,
  parseVendorContact,
  parseVendorAddress,
  parseVendorService,
  parseVendorCoverage,
  parseVendorDuplicateCandidate,
  parseVendorDuplicateSearchRow,
  parseVendorLifecycleEvent,
  parseVendorIntakeTokenIssueResult,
  parseVendorIntakeSubmitResult,
  parseVendorSelfRegistrationTarget,
  CreateVendorProfileDraftInputSchema,
  SuspendVendorProfileInputSchema,
  BlacklistVendorProfileInputSchema,
  DecideVendorProfileReviewInputSchema,
} from "./vendor-profile.ts";

const MASTER_RECORD_ID = "223e4567-e89b-12d3-a456-426614174000";
const TENANT_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";

describe("parseVendorProfile", () => {
  test("maps every field including active child counts", () => {
    const profile = parseVendorProfile({
      master_record_id: MASTER_RECORD_ID,
      tenant_id: TENANT_ID,
      vendor_code: "VND-2026-000001",
      legal_name: "PT Contoso Logistik",
      trade_name: "Contoso",
      legal_entity_type: "PT",
      business_registration_number: "REG-0001",
      vendor_category: "trucking",
      payment_term_days: 30,
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
      contact_count: 1,
      address_count: 1,
      service_count: 1,
      coverage_count: 0,
      pending_duplicate_count: 0,
    });
    assert.equal(profile.vendorCode, "VND-2026-000001");
    assert.equal(profile.lifecycleStatus, "draft");
    assert.equal(profile.contactCount, 1);
  });
});

describe("parseVendorProfileMutationResult", () => {
  test("maps a lifecycle RPC's raw app.vendor_profiles row, with no joined vendor_code/counts", () => {
    const result = parseVendorProfileMutationResult({
      master_record_id: MASTER_RECORD_ID,
      tenant_id: TENANT_ID,
      legal_name: "PT Contoso Logistik",
      trade_name: null,
      legal_entity_type: null,
      business_registration_number: null,
      vendor_category: null,
      payment_term_days: null,
      intake_source: "staff_created",
      lifecycle_status: "submitted",
      revision_reason: null,
      suspend_reason: null,
      blacklist_reason: null,
      blacklist_evidence_ref: null,
      record_version: 2,
      created_by: "staff",
      created_at: "2026-08-05T00:00:00.000Z",
      updated_at: "2026-08-05T00:01:00.000Z",
    });
    assert.equal(result.lifecycleStatus, "submitted");
    assert.equal(result.recordVersion, 2);
  });
});

describe("parseVendorProfileListRow", () => {
  test("maps a directory row", () => {
    const row = parseVendorProfileListRow({
      master_record_id: MASTER_RECORD_ID,
      vendor_code: "VND-2026-000001",
      legal_name: "PT Contoso Logistik",
      trade_name: null,
      vendor_category: "trucking",
      lifecycle_status: "active",
      intake_source: "staff_created",
      record_version: 3,
      created_at: "2026-08-05T00:00:00.000Z",
      updated_at: "2026-08-05T00:02:00.000Z",
    });
    assert.equal(row.lifecycleStatus, "active");
  });
});

describe("parseVendorContact", () => {
  test("maps an unmasked contact row", () => {
    const contact = parseVendorContact({
      id: MASTER_RECORD_ID,
      master_record_id: MASTER_RECORD_ID,
      name: "Jane Vendor",
      title: "Ops Manager",
      email: "jane@contoso-log.test",
      phone: "0811-000-001",
      is_primary: true,
      record_version: 1,
      created_at: "2026-08-05T00:00:00.000Z",
    });
    assert.equal(contact.email, "jane@contoso-log.test");
    assert.equal(contact.isPrimary, true);
  });

  test("maps a masked contact row (email/phone nulled server-side)", () => {
    const contact = parseVendorContact({
      id: MASTER_RECORD_ID,
      master_record_id: MASTER_RECORD_ID,
      name: "Jane Vendor",
      title: null,
      email: null,
      phone: null,
      is_primary: false,
      record_version: 1,
      created_at: "2026-08-05T00:00:00.000Z",
    });
    assert.equal(contact.email, null);
    assert.equal(contact.name, "Jane Vendor");
  });
});

describe("parseVendorAddress / parseVendorService / parseVendorCoverage", () => {
  test("map their respective rows", () => {
    const address = parseVendorAddress({
      id: MASTER_RECORD_ID,
      master_record_id: MASTER_RECORD_ID,
      address_type: "legal",
      street: "Jl. Sudirman 1",
      city: "Jakarta",
      province: "DKI Jakarta",
      postal_code: "10220",
      country: "Indonesia",
      record_version: 1,
      created_at: "2026-08-05T00:00:00.000Z",
    });
    assert.equal(address.addressType, "legal");

    const service = parseVendorService({
      id: MASTER_RECORD_ID,
      master_record_id: MASTER_RECORD_ID,
      service_type: "trucking",
      record_version: 1,
      created_at: "2026-08-05T00:00:00.000Z",
    });
    assert.equal(service.serviceType, "trucking");

    const coverage = parseVendorCoverage({
      id: MASTER_RECORD_ID,
      master_record_id: MASTER_RECORD_ID,
      origin_lane: "Jakarta",
      destination_lane: "Surabaya",
      record_version: 1,
      created_at: "2026-08-05T00:00:00.000Z",
    });
    assert.equal(coverage.destinationLane, "Surabaya");
  });
});

describe("parseVendorDuplicateCandidate / parseVendorDuplicateSearchRow", () => {
  test("map a pending candidate row", () => {
    const candidate = parseVendorDuplicateCandidate({
      id: MASTER_RECORD_ID,
      source_master_record_id: MASTER_RECORD_ID,
      candidate_master_record_id: TENANT_ID,
      similarity_basis: "trigram legal_name similarity",
      similarity_score: 0.72,
      decision: "pending",
      decided_by: null,
      decided_at: null,
      decided_reason: null,
      record_version: 1,
      created_at: "2026-08-05T00:00:00.000Z",
    });
    assert.equal(candidate.decision, "pending");
    assert.equal(candidate.similarityScore, 0.72);
  });

  test("maps a trigram search row", () => {
    const row = parseVendorDuplicateSearchRow({
      master_record_id: MASTER_RECORD_ID,
      vendor_code: "VND-2026-000001",
      legal_name: "PT Nusantara Cargo Ekspres",
      trade_name: null,
      similarity_score: 0.9,
    });
    assert.equal(row.similarityScore, 0.9);
  });
});

describe("parseVendorLifecycleEvent", () => {
  test("maps a lifecycle history event", () => {
    const event = parseVendorLifecycleEvent({
      id: MASTER_RECORD_ID,
      master_record_id: MASTER_RECORD_ID,
      from_status: "draft",
      to_status: "submitted",
      reason: null,
      evidence_ref: null,
      actor_label: "staff",
      occurred_at: "2026-08-05T00:00:00.000Z",
    });
    assert.equal(event.toStatus, "submitted");
  });
});

describe("parseVendorIntakeTokenIssueResult", () => {
  test("a true first issuance carries a non-null raw_token", () => {
    const result = parseVendorIntakeTokenIssueResult({
      token_id: MASTER_RECORD_ID,
      raw_token: "abc123",
      expires_at: "2026-08-12T00:00:00.000Z",
      intended_email: "invitee@newvendor.test",
    });
    assert.equal(result.rawToken, "abc123");
  });

  test("an idempotent replay carries a null raw_token", () => {
    const result = parseVendorIntakeTokenIssueResult({
      token_id: MASTER_RECORD_ID,
      raw_token: null,
      expires_at: "2026-08-12T00:00:00.000Z",
      intended_email: "invitee@newvendor.test",
    });
    assert.equal(result.rawToken, null);
  });
});

describe("parseVendorIntakeSubmitResult", () => {
  test("maps every submit_status value", () => {
    for (const status of ["ok", "not_found", "invalid", "rate_limited", "disabled", "conflict"] as const) {
      const result = parseVendorIntakeSubmitResult({ submit_status: status, master_record_id: status === "ok" ? MASTER_RECORD_ID : null });
      assert.equal(result.submitStatus, status);
    }
  });
});

describe("parseVendorSelfRegistrationTarget", () => {
  test("maps an enabled target", () => {
    const result = parseVendorSelfRegistrationTarget({ tenant_id: TENANT_ID, self_registration_enabled: true });
    assert.equal(result.tenantId, TENANT_ID);
    assert.equal(result.selfRegistrationEnabled, true);
  });

  test("maps the uniform not-available result (null tenant_id, false)", () => {
    const result = parseVendorSelfRegistrationTarget({ tenant_id: null, self_registration_enabled: false });
    assert.equal(result.tenantId, null);
    assert.equal(result.selfRegistrationEnabled, false);
  });
});

describe("CreateVendorProfileDraftInputSchema", () => {
  test("accepts a valid staff_created draft input", () => {
    const parsed = CreateVendorProfileDraftInputSchema.parse({
      tenantId: TENANT_ID,
      legalName: "PT Contoso Logistik",
      tradeName: null,
      legalEntityType: "PT",
      businessRegistrationNumber: null,
      vendorCategory: "trucking",
      paymentTermDays: 30,
      intakeSource: "staff_created",
      idempotencyKey: "idem-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "staff",
    });
    assert.equal(parsed.legalName, "PT Contoso Logistik");
  });

  test("rejects intakeSource='invited' -- that flow is token-redemption-only, never this staff-facing RPC", () => {
    assert.throws(() =>
      CreateVendorProfileDraftInputSchema.parse({
        tenantId: TENANT_ID,
        legalName: "PT Contoso Logistik",
        tradeName: null,
        legalEntityType: null,
        businessRegistrationNumber: null,
        vendorCategory: null,
        paymentTermDays: null,
        intakeSource: "invited",
        idempotencyKey: null,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "staff",
      }),
    );
  });

  test("rejects a negative payment_term_days", () => {
    assert.throws(() =>
      CreateVendorProfileDraftInputSchema.parse({
        tenantId: TENANT_ID,
        legalName: "PT Contoso Logistik",
        tradeName: null,
        legalEntityType: null,
        businessRegistrationNumber: null,
        vendorCategory: null,
        paymentTermDays: -1,
        intakeSource: "staff_created",
        idempotencyKey: null,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "staff",
      }),
    );
  });
});

describe("SuspendVendorProfileInputSchema / BlacklistVendorProfileInputSchema", () => {
  test("suspend requires a non-empty reason", () => {
    assert.throws(() =>
      SuspendVendorProfileInputSchema.parse({
        masterRecordId: MASTER_RECORD_ID,
        expectedVersion: 1,
        reason: "",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "manager",
      }),
    );
  });

  test("blacklist requires both a non-empty reason AND evidenceRef", () => {
    assert.throws(() =>
      BlacklistVendorProfileInputSchema.parse({
        masterRecordId: MASTER_RECORD_ID,
        expectedVersion: 1,
        reason: "fraud",
        evidenceRef: "",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "manager",
      }),
    );
  });
});

describe("DecideVendorProfileReviewInputSchema", () => {
  test("accepts an approve decision with a null reason", () => {
    const parsed = DecideVendorProfileReviewInputSchema.parse({
      masterRecordId: MASTER_RECORD_ID,
      expectedVersion: 1,
      decision: "approve",
      reason: null,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "reviewer",
    });
    assert.equal(parsed.decision, "approve");
  });

  test("rejects an unknown decision value", () => {
    assert.throws(() =>
      DecideVendorProfileReviewInputSchema.parse({
        masterRecordId: MASTER_RECORD_ID,
        expectedVersion: 1,
        decision: "maybe",
        reason: null,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "reviewer",
      }),
    );
  });
});
