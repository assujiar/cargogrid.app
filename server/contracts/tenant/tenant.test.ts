import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { ProvisionTenantInputSchema, TransitionTenantInputSchema, parseTenantRow } from "./tenant.ts";

describe("ProvisionTenantInputSchema", () => {
  test("accepts a well-formed provisioning request", () => {
    const parsed = ProvisionTenantInputSchema.parse({
      slug: "acme",
      name: "Acme Corp",
      idempotencyKey: "idem-1",
      requestedBy: "supreme-admin-1",
    });
    assert.equal(parsed.slug, "acme");
  });

  test("rejects an uppercase or otherwise malformed slug", () => {
    assert.throws(() => ProvisionTenantInputSchema.parse({ slug: "Acme", name: "Acme Corp", idempotencyKey: "idem-1", requestedBy: "x" }));
    assert.throws(() => ProvisionTenantInputSchema.parse({ slug: "-acme", name: "Acme Corp", idempotencyKey: "idem-1", requestedBy: "x" }));
    assert.throws(() => ProvisionTenantInputSchema.parse({ slug: "acme_corp", name: "Acme Corp", idempotencyKey: "idem-1", requestedBy: "x" }));
  });

  test("rejects an empty idempotency key or requester", () => {
    assert.throws(() => ProvisionTenantInputSchema.parse({ slug: "acme", name: "Acme Corp", idempotencyKey: "", requestedBy: "x" }));
    assert.throws(() => ProvisionTenantInputSchema.parse({ slug: "acme", name: "Acme Corp", idempotencyKey: "idem-1", requestedBy: "" }));
  });
});

describe("TransitionTenantInputSchema", () => {
  test("accepts a well-formed transition request", () => {
    const parsed = TransitionTenantInputSchema.parse({
      tenantId: "123e4567-e89b-12d3-a456-426614174000",
      newStatus: "active",
      reason: "bootstrap complete",
      requestedBy: "supreme-admin-1",
    });
    assert.equal(parsed.newStatus, "active");
  });

  test("rejects a status outside the canonical enum", () => {
    assert.throws(() =>
      TransitionTenantInputSchema.parse({
        tenantId: "123e4567-e89b-12d3-a456-426614174000",
        newStatus: "deleted",
        reason: "x",
        requestedBy: "x",
      }),
    );
  });

  test("rejects a non-UUID tenantId", () => {
    assert.throws(() => TransitionTenantInputSchema.parse({ tenantId: "not-a-uuid", newStatus: "active", reason: "x", requestedBy: "x" }));
  });
});

describe("parseTenantRow", () => {
  const RAW_ROW = {
    id: "123e4567-e89b-12d3-a456-426614174000",
    slug: "acme",
    name: "Acme Corp",
    canonical_status: "provisioning",
    plan_snapshot: {},
    idempotency_key: "idem-1",
    requested_by: "supreme-admin-1",
    reason: null,
    legal_hold: false,
    record_version: 1,
    effective_from: null,
    effective_until: null,
    activated_at: null,
    deactivated_at: null,
    terminated_at: null,
    created_at: "2026-07-16T00:00:00.000Z",
    updated_at: "2026-07-16T00:00:00.000Z",
  };

  test("maps a real snake_case Postgres row to the camelCase contract shape", () => {
    const tenant = parseTenantRow(RAW_ROW);
    assert.equal(tenant.id, RAW_ROW.id);
    assert.equal(tenant.canonicalStatus, "provisioning");
    assert.equal(tenant.idempotencyKey, "idem-1");
    assert.equal(tenant.recordVersion, 1);
  });

  test("rejects a row with an out-of-enum canonical_status (defense against a future schema drift)", () => {
    assert.throws(() => parseTenantRow({ ...RAW_ROW, canonical_status: "archived" }));
  });

  test("rejects a row missing a required field", () => {
    const { slug: _slug, ...withoutSlug } = RAW_ROW;
    assert.throws(() => parseTenantRow(withoutSlug));
  });
});
