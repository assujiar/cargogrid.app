import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  BrandTokensSchema,
  DocumentTemplateRefsSchema,
  SetTenantBrandTokensInputSchema,
  parseTenantBrandVersion,
  parseEffectiveTenantBrand,
} from "./white-label.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";

const ROW = {
  id: VERSION_ID,
  tenant_id: TENANT_ID,
  version_number: 1,
  status: "draft",
  tokens: { primary: "#171717" },
  logo_asset_url: "https://storage.example.test/acme/logo.png",
  email_sender_name: "Acme Logistics",
  email_logo_asset_url: null,
  document_template_refs: {},
  contrast_validated: true,
  contrast_report: { primary_vs_neutral_50: 15.2, threshold: 4.5 },
  cloned_from_version_id: null,
  rollback_of_version_id: null,
  effective_from: null,
  created_by: "tester",
  published_by: null,
  published_at: null,
  archived_at: null,
  archived_reason: null,
  record_version: 1,
  created_at: "2026-07-17T00:00:00.000Z",
  updated_at: "2026-07-17T00:00:00.000Z",
};

describe("BrandTokensSchema", () => {
  test("accepts an empty object (no color chosen yet)", () => {
    assert.deepEqual(BrandTokensSchema.parse({}), {});
  });

  test("accepts primary/secondary hex colors", () => {
    const parsed = BrandTokensSchema.parse({ primary: "#171717", secondary: "#404040" });
    assert.equal(parsed.primary, "#171717");
  });

  test("rejects a malformed hex color", () => {
    assert.throws(() => BrandTokensSchema.parse({ primary: "red" }));
  });

  test("rejects a key outside RPD-019's fixed color surface (strict schema)", () => {
    assert.throws(() => BrandTokensSchema.parse({ primary: "#171717", accent: "#ff0000" } as never));
  });
});

describe("DocumentTemplateRefsSchema", () => {
  test("accepts the whitelisted keys only", () => {
    const parsed = DocumentTemplateRefsSchema.parse({
      invoiceLetterheadUrl: "https://storage.example.test/acme/letterhead.png",
      emailFooterText: "Thank you for shipping with Acme.",
    });
    assert.equal(parsed.emailFooterText, "Thank you for shipping with Acme.");
  });

  test("rejects an arbitrary key (no open-ended template surface)", () => {
    assert.throws(() => DocumentTemplateRefsSchema.parse({ customScript: "alert(1)" } as never));
  });

  test("rejects free text containing an angle bracket (no HTML/script injection)", () => {
    assert.throws(() => DocumentTemplateRefsSchema.parse({ emailFooterText: "<script>alert(1)</script>" }));
  });

  test("rejects a non-https asset URL", () => {
    assert.throws(() => DocumentTemplateRefsSchema.parse({ invoiceLetterheadUrl: "javascript:alert(1)" }));
  });
});

describe("SetTenantBrandTokensInputSchema", () => {
  test("defaults tokens/logoAssetUrl/documentTemplateRefs when omitted", () => {
    const parsed = SetTenantBrandTokensInputSchema.parse({
      versionId: VERSION_ID,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tenant admin",
    });
    assert.deepEqual(parsed.tokens, {});
    assert.equal(parsed.logoAssetUrl, null);
    assert.deepEqual(parsed.documentTemplateRefs, {});
  });

  test("rejects a data: URI logo asset (injection defense)", () => {
    assert.throws(() =>
      SetTenantBrandTokensInputSchema.parse({
        versionId: VERSION_ID,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "tenant admin",
        logoAssetUrl: "data:text/html,<script>alert(1)</script>",
      }),
    );
  });
});

describe("parseTenantBrandVersion", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const version = parseTenantBrandVersion(ROW);
    assert.equal(version.tenantId, TENANT_ID);
    assert.equal(version.contrastValidated, true);
    assert.deepEqual(version.tokens, { primary: "#171717" });
  });

  test("accepts a fully null draft (no tokens/assets set yet)", () => {
    const version = parseTenantBrandVersion({
      ...ROW,
      tokens: {},
      logo_asset_url: null,
      email_sender_name: null,
      contrast_validated: false,
      contrast_report: null,
    });
    assert.deepEqual(version.tokens, {});
    assert.equal(version.contrastValidated, false);
  });
});

describe("parseEffectiveTenantBrand", () => {
  test("maps the tenant-source evaluator row shape", () => {
    const brand = parseEffectiveTenantBrand({
      tenant_id: TENANT_ID,
      source: "tenant",
      version_id: VERSION_ID,
      version_number: 1,
      tokens: { primary: "#171717" },
      logo_asset_url: null,
      email_sender_name: null,
      email_logo_asset_url: null,
      document_template_refs: {},
      effective_from: "2026-07-17T00:00:00.000Z",
    });
    assert.equal(brand.source, "tenant");
    assert.equal(brand.versionId, VERSION_ID);
  });

  test("maps the default-fallback evaluator row shape (no version)", () => {
    const brand = parseEffectiveTenantBrand({
      tenant_id: TENANT_ID,
      source: "default",
      version_id: null,
      version_number: null,
      tokens: { primary: "#171717", secondary: "#171717" },
      logo_asset_url: null,
      email_sender_name: null,
      email_logo_asset_url: null,
      document_template_refs: {},
      effective_from: null,
    });
    assert.equal(brand.source, "default");
    assert.equal(brand.versionId, null);
  });
});
