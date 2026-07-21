import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { HostnameSchema, parseTenantCustomDomain, parseResolvedTenantDomain } from "./custom-domain.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const DOMAIN_ID = "323e4567-e89b-12d3-a456-426614174000";

const ROW = {
  id: DOMAIN_ID,
  tenant_id: TENANT_ID,
  hostname: "shipping.acme.example",
  status: "pending_verification",
  verification_method: "dns_txt",
  verification_token: "abc123",
  verification_challenge_host: "_cargogrid-verify.shipping.acme.example",
  requested_by: "tenant admin",
  verified_at: null,
  verified_by: null,
  activated_at: null,
  activated_by: null,
  disabled_at: null,
  disabled_by: null,
  disabled_reason: null,
  rejected_at: null,
  rejected_by: null,
  rejected_reason: null,
  expires_at: "2026-07-24T00:00:00.000Z",
  record_version: 1,
  created_at: "2026-07-17T00:00:00.000Z",
  updated_at: "2026-07-17T00:00:00.000Z",
};

describe("HostnameSchema", () => {
  test("accepts a well-formed two-label hostname", () => {
    assert.equal(HostnameSchema.parse("shipping.acme.example"), "shipping.acme.example");
  });

  test("accepts a punycode-encoded IDN label", () => {
    assert.equal(HostnameSchema.parse("xn--caf-dma.example.test"), "xn--caf-dma.example.test");
  });

  test("rejects a raw Unicode IDN label (no homograph support)", () => {
    assert.throws(() => HostnameSchema.parse("café.example.test"));
  });

  test("rejects a bare single-label hostname", () => {
    assert.throws(() => HostnameSchema.parse("localhost"));
  });

  test("rejects an uppercase hostname (must be normalized by the caller first)", () => {
    assert.throws(() => HostnameSchema.parse("ACME.example.test"));
  });

  test("rejects an IPv4-literal string", () => {
    assert.throws(() => HostnameSchema.parse("192.168.1.1"));
  });
});

describe("parseTenantCustomDomain", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const domain = parseTenantCustomDomain(ROW);
    assert.equal(domain.tenantId, TENANT_ID);
    assert.equal(domain.status, "pending_verification");
    assert.equal(domain.verificationChallengeHost, "_cargogrid-verify.shipping.acme.example");
  });

  test("accepts an active row with every lifecycle field populated", () => {
    const domain = parseTenantCustomDomain({
      ...ROW,
      status: "active",
      verified_at: "2026-07-18T00:00:00.000Z",
      verified_by: "tenant admin",
      activated_at: "2026-07-18T01:00:00.000Z",
      activated_by: "tenant admin",
    });
    assert.equal(domain.status, "active");
    assert.equal(domain.activatedBy, "tenant admin");
  });
});

describe("parseResolvedTenantDomain", () => {
  test("maps a raw resolver row to the camelCase contract shape", () => {
    const resolved = parseResolvedTenantDomain({
      domain_id: DOMAIN_ID,
      resolved_tenant_id: TENANT_ID,
      tenant_canonical_status: "active",
    });
    assert.equal(resolved.resolvedTenantId, TENANT_ID);
    assert.equal(resolved.tenantCanonicalStatus, "active");
  });
});
