import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseStatusSet,
  parseCanonicalStatus,
  parseStatusLegacyMapping,
  parseResolvedStatusPresentation,
  RegisterCanonicalStatusInputSchema,
  ResolveStatusPresentationInputSchema,
} from "./status.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const STATUS_ID = "323e4567-e89b-12d3-a456-426614174000";
const MAPPING_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

describe("parseStatusSet", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const set = parseStatusSet({
      code: "quotation_status",
      name: "Quotation Status",
      owner_primitive_code: "STAT",
      registered_by: "platform-core-foundation",
      created_at: "2026-07-19T00:00:00.000Z",
    });
    assert.equal(set.ownerPrimitiveCode, "STAT");
  });
});

describe("parseCanonicalStatus", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const status = parseCanonicalStatus({
      id: STATUS_ID,
      status_set_code: "quotation_status",
      code: "draft",
      category: "initial",
      sort_order: 0,
      registered_by: "platform-core-foundation",
      created_at: "2026-07-19T00:00:00.000Z",
      is_terminal: false,
    });
    assert.equal(status.category, "initial");
    assert.equal(status.isTerminal, false);
  });
});

describe("parseStatusLegacyMapping", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const mapping = parseStatusLegacyMapping({
      id: MAPPING_ID,
      status_set_code: "quotation_status",
      legacy_value: "PENDING",
      canonical_status_id: STATUS_ID,
      registered_by: "tester",
      created_at: "2026-07-19T00:00:00.000Z",
    });
    assert.equal(mapping.legacyValue, "PENDING");
    assert.equal(mapping.canonicalStatusId, STATUS_ID);
  });
});

describe("parseResolvedStatusPresentation", () => {
  test("maps a raw app.resolve_status_presentation() row", () => {
    const resolved = parseResolvedStatusPresentation({
      canonical_status_code: "draft",
      category: "initial",
      is_terminal: false,
      resolved_label: "Draft",
      resolved_color: "#6b7280",
      resolved_icon: "circle-dashed",
      is_fallback: false,
      resolved_version_id: STATUS_ID,
    });
    assert.equal(resolved.resolvedLabel, "Draft");
    assert.equal(resolved.isFallback, false);
  });

  test("maps a fallback row with a null resolved_version_id", () => {
    const resolved = parseResolvedStatusPresentation({
      canonical_status_code: "draft",
      category: "initial",
      is_terminal: false,
      resolved_label: "Draft",
      resolved_color: null,
      resolved_icon: "circle",
      is_fallback: true,
      resolved_version_id: null,
    });
    assert.equal(resolved.isFallback, true);
    assert.equal(resolved.resolvedVersionId, null);
  });
});

describe("RegisterCanonicalStatusInputSchema", () => {
  test("defaults sortOrder to 0", () => {
    const parsed = RegisterCanonicalStatusInputSchema.parse({
      statusSetCode: "quotation_status",
      code: "draft",
      category: "initial",
      actorAuthUserId: ACTOR_ID,
      registeredBy: "tester",
    });
    assert.equal(parsed.sortOrder, 0);
  });

  test("rejects an unknown category", () => {
    assert.throws(() =>
      RegisterCanonicalStatusInputSchema.parse({
        statusSetCode: "quotation_status",
        code: "draft",
        category: "pending",
        actorAuthUserId: ACTOR_ID,
        registeredBy: "tester",
      }),
    );
  });
});

describe("ResolveStatusPresentationInputSchema", () => {
  test("defaults company/branch/role/user ids to null", () => {
    const parsed = ResolveStatusPresentationInputSchema.parse({
      statusSetCode: "quotation_status",
      canonicalStatusCode: "draft",
      tenantId: TENANT_ID,
    });
    assert.equal(parsed.companyId, null);
    assert.equal(parsed.branchId, null);
    assert.equal(parsed.roleId, null);
    assert.equal(parsed.userId, null);
  });
});
